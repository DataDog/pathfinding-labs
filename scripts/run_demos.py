#!/usr/bin/env python3
"""
Run demo_attack.sh scripts for one or more labs and capture raw transcript output.

The captured files preserve ANSI color codes exactly as produced by the scripts.
Run redact_transcripts.py on the output directory before committing transcripts.

Lab IDs match the pathfinding.cloud slug format derived from scenario.yaml
(e.g. iam-001, sts-001, iam-002-to-bucket).

Usage:
    # Run demos for specific labs (must be deployed):
    python run_demos.py --labs iam-001 sts-001 --output-dir /tmp/demos-raw/

    # Run all labs that have a demo script (4 concurrent by default):
    python run_demos.py --all --output-dir /tmp/demos-raw/

    # Run with more parallelism:
    python run_demos.py --all --workers 8 --output-dir /tmp/demos-raw/

    # List available labs with demo scripts:
    python run_demos.py --list
"""

import argparse
import concurrent.futures
import os
import subprocess
import sys
import threading
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

# Root of the pathfinding-labs repo (two levels up from this script)
REPO_ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_ROOT = REPO_ROOT / "modules" / "scenarios"
DEFAULT_OUTPUT_DIR = Path("/tmp/pathfinding-demos")
DEFAULT_WORKERS = 4

# Lock so concurrent workers don't interleave their print output
_print_lock = threading.Lock()


def log(msg: str):
    with _print_lock:
        print(msg, flush=True)


def find_demo_scripts():
    """Scan scenarios directory for all demo_attack.sh files.

    Returns a list of dicts: {slug, path, scenario_dir}
    """
    found = []
    for script_path in sorted(SCENARIOS_ROOT.rglob("demo_attack.sh")):
        scenario_dir = script_path.parent
        slug = derive_slug(scenario_dir)
        found.append({
            "slug": slug,
            "path": script_path,
            "scenario_dir": scenario_dir,
        })
    return found


def derive_slug(scenario_dir: Path) -> str:
    """Derive the pathfinding.cloud URL slug for a scenario.

    Mirrors generate_slug() in pathfinding.cloud/scripts/generate-labs-json.py:
      - to-admin  → just the pathfinding-cloud-id  (e.g. "sts-001")
      - to-bucket → cloud-id + "-to-bucket"         (e.g. "sts-001-to-bucket")
      - other target → cloud-id + "-" + target
      - no cloud-id → directory name

    This ensures transcript filenames match the slugs used in labs.json and
    the per-lab JSON files, so hasDemoTranscript detection works correctly.
    """
    scenario_yaml = scenario_dir / "scenario.yaml"
    if scenario_yaml.exists() and yaml is not None:
        try:
            data = yaml.safe_load(scenario_yaml.read_text(encoding="utf-8"))
            cloud_id = (data or {}).get("pathfinding-cloud-id", "").strip()
            target = (data or {}).get("target", "").strip()
            if cloud_id:
                if target == "to-admin" or not target:
                    return cloud_id
                return f"{cloud_id}-{target}"
        except Exception:
            pass
    return scenario_dir.name


# Default per-demo and per-cleanup timeouts (seconds). Override per scenario by setting
# demo_timeout_seconds / cleanup_timeout_seconds in scenario.yaml — needed for slow scenarios
# like glue-001 where the dev endpoint alone takes 10–15 min to provision.
DEFAULT_DEMO_TIMEOUT = 300
DEFAULT_CLEANUP_TIMEOUT = 120


def read_scenario_timeouts(scenario_dir: Path) -> tuple[int, int]:
    """Return (demo_timeout, cleanup_timeout) for a scenario, falling back to defaults.

    Reads optional demo_timeout_seconds / cleanup_timeout_seconds from scenario.yaml.
    Non-integer values are ignored with a silent fallback to the default.
    """
    demo_timeout = DEFAULT_DEMO_TIMEOUT
    cleanup_timeout = DEFAULT_CLEANUP_TIMEOUT
    scenario_yaml = scenario_dir / "scenario.yaml"
    if scenario_yaml.exists() and yaml is not None:
        try:
            data = yaml.safe_load(scenario_yaml.read_text(encoding="utf-8")) or {}
            demo_timeout = int(data.get("demo_timeout_seconds", DEFAULT_DEMO_TIMEOUT))
            cleanup_timeout = int(data.get("cleanup_timeout_seconds", DEFAULT_CLEANUP_TIMEOUT))
        except Exception:
            pass
    return demo_timeout, cleanup_timeout


def run_demo(entry: dict, output_dir: Path, skip_check: bool = False, cleanup: bool = True) -> tuple[bool, str]:
    """Run demo_attack.sh for a single scenario, save the transcript, then run cleanup.

    cleanup_attack.sh is always run after the demo (even on failure) unless
    cleanup=False, to ensure no demo artifacts are left behind.

    Returns (success, slug).
    Output is buffered and printed atomically after the script finishes
    so concurrent runs don't interleave.
    """
    script_path = entry["path"]
    scenario_dir = entry["scenario_dir"]
    slug = entry["slug"]
    output_file = output_dir / f"{slug}.txt"
    cleanup_path = scenario_dir / "cleanup_attack.sh"
    demo_timeout, cleanup_timeout = read_scenario_timeouts(scenario_dir)

    lines = [f"  [{slug}] starting..."]

    if not skip_check and not os.access(script_path, os.X_OK):
        lines.append(f"  [{slug}] WARNING: not executable, skipping. Run: chmod +x {script_path}")
        log("\n".join(lines))
        return False, slug

    demo_ok = False
    try:
        result = subprocess.run(
            ["bash", str(script_path)],
            cwd=str(scenario_dir),
            capture_output=True,
            # Do not set text=True — preserve raw bytes for ANSI codes
            timeout=demo_timeout,
        )
        combined = result.stdout + result.stderr
        output_file.write_bytes(combined)

        if result.returncode != 0:
            lines.append(f"  [{slug}] WARNING: demo exited with code {result.returncode}")
        else:
            lines.append(f"  [{slug}] demo done — {len(combined):,} bytes -> {output_file.name}")
        demo_ok = result.returncode == 0

    except subprocess.TimeoutExpired:
        lines.append(f"  [{slug}] ERROR: demo timed out after {demo_timeout}s")
    except Exception as e:
        lines.append(f"  [{slug}] ERROR: {e}")

    # Always run cleanup after the demo, regardless of demo success
    if cleanup and cleanup_path.exists():
        try:
            cleanup_result = subprocess.run(
                ["bash", str(cleanup_path)],
                cwd=str(scenario_dir),
                capture_output=True,
                timeout=cleanup_timeout,
            )
            if cleanup_result.returncode != 0:
                lines.append(f"  [{slug}] WARNING: cleanup exited with code {cleanup_result.returncode}")
            else:
                lines.append(f"  [{slug}] cleanup done")
        except subprocess.TimeoutExpired:
            lines.append(f"  [{slug}] WARNING: cleanup timed out after {cleanup_timeout}s")
        except Exception as e:
            lines.append(f"  [{slug}] WARNING: cleanup error: {e}")
    elif cleanup and not cleanup_path.exists():
        lines.append(f"  [{slug}] WARNING: no cleanup_attack.sh found")

    log("\n".join(lines))
    return demo_ok, slug


def run_demos_concurrent(targets: list, output_dir: Path, workers: int, skip_check: bool, cleanup: bool) -> tuple[int, int]:
    """Run demos in parallel batches. Returns (success_count, failure_count)."""
    success = 0
    failure = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(run_demo, entry, output_dir, skip_check, cleanup): entry["slug"]
            for entry in targets
        }
        for future in concurrent.futures.as_completed(futures):
            ok, slug = future.result()
            if ok:
                success += 1
            else:
                failure += 1

    return success, failure


def main():
    parser = argparse.ArgumentParser(
        description="Run demo_attack.sh scripts and capture raw transcripts.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--labs", nargs="+", metavar="SLUG",
        help="One or more lab slugs (pathfinding.cloud format, e.g. iam-001 sts-001-to-bucket)",
    )
    group.add_argument(
        "--all", action="store_true",
        help="Run all labs that have a demo_attack.sh script",
    )
    group.add_argument(
        "--list", action="store_true",
        help="List labs that have demo scripts and exit",
    )
    parser.add_argument(
        "--output-dir", metavar="PATH", default=str(DEFAULT_OUTPUT_DIR),
        help=f"Directory to write raw transcript files (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--workers", type=int, default=DEFAULT_WORKERS, metavar="N",
        help=f"Number of demos to run concurrently (default: {DEFAULT_WORKERS})",
    )
    parser.add_argument(
        "--skip-check", action="store_true",
        help="Skip pre-flight checks (e.g. executable bit)",
    )
    parser.add_argument(
        "--no-cleanup", action="store_true",
        help="Skip running cleanup_attack.sh after each demo",
    )
    args = parser.parse_args()

    all_demos = find_demo_scripts()

    if args.list:
        print(f"Found {len(all_demos)} lab(s) with demo_attack.sh:")
        for entry in all_demos:
            print(f"  {entry['slug']:<60}  {entry['scenario_dir'].relative_to(REPO_ROOT)}")
        return

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.all:
        targets = all_demos
    else:
        slug_map = {entry["slug"]: entry for entry in all_demos}
        targets = []
        for requested_slug in args.labs:
            if requested_slug in slug_map:
                targets.append(slug_map[requested_slug])
            else:
                print(f"WARNING: No demo script found for '{requested_slug}'", file=sys.stderr)
                available = [e["slug"] for e in all_demos if requested_slug in e["slug"]]
                if available:
                    print(f"  Did you mean one of: {', '.join(available)}", file=sys.stderr)

    if not targets:
        print("No demo scripts to run.", file=sys.stderr)
        sys.exit(1)

    workers = min(args.workers, len(targets))
    cleanup = not args.no_cleanup
    print(f"Running {len(targets)} demo(s) with {workers} concurrent worker(s) -> {output_dir}")
    if not cleanup:
        print("  Cleanup disabled (--no-cleanup)")

    success, failure = run_demos_concurrent(targets, output_dir, workers, args.skip_check, cleanup)

    print(f"\nDone: {success} succeeded, {failure} failed.")
    print(f"Next step: run redact_transcripts.py on {output_dir} before committing.")
    if failure:
        sys.exit(1)


if __name__ == "__main__":
    main()

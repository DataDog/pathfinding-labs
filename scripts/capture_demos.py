#!/usr/bin/env python3
"""
Full demo capture pipeline for currently enabled scenarios.

Steps:
  1. Query `plabs scenarios list --enabled` to get enabled lab IDs
  2. Run demo_attack.sh for each via run_demos.py  (raw output -> /tmp)
  3. Redact credentials and account IDs via redact_transcripts.py
  4. Copy redacted transcripts into pathfinding.cloud/docs/labs/demo-transcripts/
  5. Regenerate pathfinding.cloud labs JSON (hasDemoTranscript detection)

Usage:
    python capture_demos.py
    python capture_demos.py --dry-run      # show plan, make no changes
    python capture_demos.py --skip-run     # skip step 2 (re-use existing raw files in /tmp)
    python capture_demos.py --skip-json    # skip step 5 (don't regenerate JSON)
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Repo layout (this script lives in pathfinding-labs/scripts/)
# ---------------------------------------------------------------------------
LABS_REPO   = Path(__file__).resolve().parent.parent
CLOUD_REPO  = LABS_REPO.parent / "pathfinding.cloud"
PLABS_BIN   = LABS_REPO / "plabs"
SCRIPTS_DIR = LABS_REPO / "scripts"
DEMOS_DIR   = CLOUD_REPO / "docs" / "labs" / "demo-transcripts"
RAW_DIR     = Path("/tmp/pathfinding-demos-raw")

RUN_DEMOS_SCRIPT    = SCRIPTS_DIR / "run_demos.py"
REDACT_SCRIPT       = SCRIPTS_DIR / "redact_transcripts.py"
GENERATE_JSON_SCRIPT = CLOUD_REPO / "scripts" / "generate-labs-json.py"


def check_prerequisites():
    """Verify required files and repos exist before starting."""
    ok = True
    if not PLABS_BIN.exists():
        print(f"ERROR: plabs binary not found at {PLABS_BIN}")
        print(f"       Run: cd {LABS_REPO} && make build")
        ok = False
    if not CLOUD_REPO.exists():
        print(f"ERROR: pathfinding.cloud repo not found at {CLOUD_REPO}")
        ok = False
    if not RUN_DEMOS_SCRIPT.exists():
        print(f"ERROR: {RUN_DEMOS_SCRIPT} not found")
        ok = False
    if not REDACT_SCRIPT.exists():
        print(f"ERROR: {REDACT_SCRIPT} not found")
        ok = False
    if not GENERATE_JSON_SCRIPT.exists():
        print(f"ERROR: {GENERATE_JSON_SCRIPT} not found")
        ok = False
    return ok


def get_enabled_unique_ids() -> list[str]:
    """Run `plabs status` and extract UniqueIDs of enabled scenarios.

    Parses lines like:
        * iam-001-to-admin     deployed
        * sts-001-to-admin     deployed ⚠ demo active
    Returns a list of UniqueIDs, e.g. ['iam-001-to-admin', 'sts-001-to-admin']
    """
    result = subprocess.run(
        [str(PLABS_BIN), "status"],
        cwd=str(LABS_REPO),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"ERROR: plabs status failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    unique_ids = []
    in_enabled_section = False
    for line in result.stdout.splitlines():
        if "Enabled Scenarios" in line:
            in_enabled_section = True
            continue
        if in_enabled_section:
            match = re.match(r"\s*\*\s+([\w\-+]+)", line)
            if match:
                unique_ids.append(match.group(1))
            elif line.strip().startswith("---"):
                # Next section started
                in_enabled_section = False

    return unique_ids


def uniqueid_to_slug(uid: str) -> str:
    """Convert a plabs UniqueID to a pathfinding.cloud URL slug.

    Mirrors generate_slug() in pathfinding.cloud/scripts/generate-labs-json.py:
      - {cloud-id}-to-bucket → {cloud-id}-to-bucket  (suffix kept)
      - {cloud-id}-to-admin  → {cloud-id}             (suffix dropped)
      - {cloud-id}-{other}   → {cloud-id}             (suffix dropped)
    """
    if uid.endswith("-to-bucket"):
        return uid
    idx = uid.rfind("-to-")
    if idx != -1:
        return uid[:idx]
    return uid


def run_step(description: str, cmd: list[str], dry_run: bool, cwd: str = None) -> bool:
    """Print and optionally run a shell command. Returns True on success."""
    print(f"\n{'[dry-run] ' if dry_run else ''}$ {' '.join(str(c) for c in cmd)}")
    if dry_run:
        return True
    result = subprocess.run(cmd, cwd=cwd)
    if result.returncode != 0:
        print(f"ERROR: {description} failed (exit {result.returncode})", file=sys.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Full demo capture pipeline for enabled pathfinding-labs scenarios.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--dry-run",   action="store_true", help="Print plan without executing")
    parser.add_argument("--skip-run",  action="store_true", help="Skip running demo scripts (re-use existing raw files in /tmp)")
    parser.add_argument("--skip-json", action="store_true", help="Skip regenerating pathfinding.cloud labs JSON")
    parser.add_argument("--workers",    type=int, default=4, metavar="N", help="Concurrent demo workers (default: 4)")
    parser.add_argument("--no-cleanup", action="store_true", help="Skip cleanup_attack.sh after each demo")
    parser.add_argument(
        "--labs-source-dir", metavar="PATH", default=str(LABS_REPO),
        help=f"Path to pathfinding-labs repo (default: {LABS_REPO})",
    )
    args = parser.parse_args()

    if not check_prerequisites():
        sys.exit(1)

    # ------------------------------------------------------------------
    # Step 1: Get enabled scenarios
    # ------------------------------------------------------------------
    print("Step 1: Querying enabled scenarios from plabs...")
    unique_ids = get_enabled_unique_ids()

    if not unique_ids:
        print("No enabled scenarios found. Enable some with: plabs enable <id>")
        sys.exit(0)

    slugs = [uniqueid_to_slug(uid) for uid in unique_ids]

    print(f"  Found {len(unique_ids)} enabled scenario(s):")
    for uid, slug in zip(unique_ids, slugs):
        print(f"    {uid:<45} → slug: {slug}")

    # ------------------------------------------------------------------
    # Step 2: Run demo scripts
    # ------------------------------------------------------------------
    if not args.skip_run:
        print(f"\nStep 2: Running demo scripts -> {RAW_DIR}")
        cmd = ([sys.executable, str(RUN_DEMOS_SCRIPT), "--labs"] + slugs
               + ["--output-dir", str(RAW_DIR), "--workers", str(args.workers)])
        if args.no_cleanup:
            cmd.append("--no-cleanup")
        ok = run_step("run_demos", cmd, dry_run=args.dry_run)
        if not ok and not args.dry_run:
            print("WARNING: Some demos failed. Continuing with redaction of whatever was captured.")
    else:
        print(f"\nStep 2: Skipped (--skip-run). Using existing files in {RAW_DIR}")

    # ------------------------------------------------------------------
    # Step 3: Redact
    # ------------------------------------------------------------------
    print(f"\nStep 3: Redacting transcripts -> {DEMOS_DIR}")
    if not args.dry_run:
        DEMOS_DIR.mkdir(parents=True, exist_ok=True)
    ok = run_step(
        "redact_transcripts",
        [sys.executable, str(REDACT_SCRIPT), str(RAW_DIR), "--output-dir", str(DEMOS_DIR)],
        dry_run=args.dry_run,
    )
    if not ok and not args.dry_run:
        sys.exit(1)

    # ------------------------------------------------------------------
    # Step 4: Regenerate labs JSON
    # ------------------------------------------------------------------
    if not args.skip_json:
        print(f"\nStep 4: Regenerating pathfinding.cloud labs JSON...")
        ok = run_step(
            "generate-labs-json",
            [sys.executable, str(GENERATE_JSON_SCRIPT), "--source-dir", args.labs_source_dir],
            dry_run=args.dry_run,
            cwd=str(CLOUD_REPO),
        )
        if not ok and not args.dry_run:
            sys.exit(1)
    else:
        print("\nStep 4: Skipped (--skip-json)")

    print(f"\n{'[dry-run] ' if args.dry_run else ''}Done.")
    if not args.dry_run:
        print(f"  Transcripts committed to: {DEMOS_DIR}")
        print(f"  Run the dev server to verify: cd {CLOUD_REPO}/docs && python3 dev-server.py")


if __name__ == "__main__":
    main()

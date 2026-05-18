#!/usr/bin/env python3
"""
Insert `export AWS_DEFAULT_REGION="$AWS_REGION"` after every `export AWS_REGION...`
line in demo_attack.sh / cleanup_attack.sh scripts.

The AWS CLI v1 (and some v2 configs) only honor AWS_DEFAULT_REGION for region
resolution, not AWS_REGION. Without both, regional API calls (ssm, ec2, lambda,
etc.) fail with "You must specify a region" after assume-role strips inherited
shared-config region.

Idempotent: skips if an `export AWS_DEFAULT_REGION` line already immediately
follows the `export AWS_REGION` line.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_DIR = REPO_ROOT / "modules" / "scenarios"

EXPORT_RE = re.compile(r"^(\s*)export\s+AWS_REGION(\b|=)")
DEFAULT_RE = re.compile(r"^\s*export\s+AWS_DEFAULT_REGION\b")

def fix_file(path: Path) -> int:
    original = path.read_text()
    lines = original.splitlines(keepends=True)
    out = []
    inserted = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = EXPORT_RE.match(line)
        if m:
            # Peek at next line; skip if it already exports AWS_DEFAULT_REGION
            next_line = lines[i + 1] if i + 1 < len(lines) else ""
            if not DEFAULT_RE.match(next_line):
                indent = m.group(1)
                # Preserve the trailing newline style of the matched line
                newline = "\n" if line.endswith("\n") else ""
                out.append(f'{indent}export AWS_DEFAULT_REGION="$AWS_REGION"{newline}')
                inserted += 1
        i += 1
    new_text = "".join(out)
    if new_text != original:
        path.write_text(new_text)
    return inserted

def main():
    files = sorted(SCENARIOS_DIR.rglob("*.sh"))
    total_files_changed = 0
    total_insertions = 0
    for f in files:
        inserted = fix_file(f)
        if inserted:
            rel = f.relative_to(REPO_ROOT)
            print(f"  {inserted:>2}  {rel}")
            total_files_changed += 1
            total_insertions += inserted
    print()
    print(f"Files changed: {total_files_changed}")
    print(f"Lines inserted: {total_insertions}")

if __name__ == "__main__":
    main()

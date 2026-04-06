#!/usr/bin/env python3
"""
Phase 2.5 Migration Script: Demo Restriction Pattern
Adds demo_permissions.sh sourcing, restrict/restore calls to demo_attack.sh
and safety restore to cleanup_attack.sh.

Usage: python3 scripts/migrate_demo_restriction_phase2_5.py [--dry-run]
"""

import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS_DIR = os.path.join(PROJECT_ROOT, "modules", "scenarios")

ALREADY_MIGRATED_MARKER = "restrict_helpful_permissions"
RESTORE_MARKER = "restore_helpful_permissions"

# The source + restrict block to insert after credential helpers
DEMO_SOURCE_AND_RESTRICT = """
# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"
"""

# Cross-account scenarios are one level deeper
DEMO_SOURCE_AND_RESTRICT_CROSS_ACCOUNT = """
# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"
"""

# The restore line to insert before the success summary
DEMO_RESTORE = '# Restore helpful permissions for manual exploration\nrestore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"\n'

# Cleanup script additions
CLEANUP_SOURCE_AND_RESTORE = """# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
"""

CLEANUP_SOURCE_AND_RESTORE_CROSS_ACCOUNT = """# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
"""


def is_cross_account(path):
    """Check if this is a cross-account scenario (deeper nesting)."""
    return "cross-account" in path


def is_eol(path):
    """Check if this is an end-of-life scenario (different nesting)."""
    return "end-of-life" in path


def get_depth_prefix(path):
    """Determine the correct relative path depth for scripts/lib/."""
    # Count directory levels from scenario dir to project root
    scenario_dir = os.path.dirname(path)
    rel = os.path.relpath(scenario_dir, PROJECT_ROOT)
    depth = len(rel.split(os.sep))
    return "/".join([".."] * depth)


def migrate_demo_script(path, dry_run=False):
    """Add restriction pattern to a demo_attack.sh."""
    with open(path) as f:
        content = f.read()

    if ALREADY_MIGRATED_MARKER in content:
        return False, "Already migrated"

    # Determine the correct depth prefix
    depth_prefix = get_depth_prefix(path)

    source_block = f'''
# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/{depth_prefix}/scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"
'''

    restore_block = f'# Restore helpful permissions for manual exploration\nrestore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"\n'

    new_content = content

    # Strategy 1: Insert after use_readonly_creds() function definition
    # Look for the pattern: use_readonly_creds() { ... } followed by a blank line or comment
    readonly_pattern = re.compile(
        r'(use_readonly_creds\(\)\s*\{[^}]+\})\n',
        re.DOTALL
    )
    match = readonly_pattern.search(new_content)
    if match:
        insert_pos = match.end()
        new_content = new_content[:insert_pos] + source_block + new_content[insert_pos:]
    else:
        # Strategy 2: Insert after use_starting_creds() function definition
        starting_pattern = re.compile(
            r'(use_starting_creds\(\)\s*\{[^}]+\})\n',
            re.DOTALL
        )
        match = starting_pattern.search(new_content)
        if match:
            insert_pos = match.end()
            new_content = new_content[:insert_pos] + source_block + new_content[insert_pos:]
        else:
            # Strategy 3: Insert after "cd - > /dev/null" (return to scenario dir)
            cd_pattern = re.compile(r'(cd - > /dev/null\n)')
            matches = list(cd_pattern.finditer(new_content))
            if matches:
                # Use the first cd - (after retrieving creds)
                insert_pos = matches[0].end()
                new_content = new_content[:insert_pos] + source_block + new_content[insert_pos:]
            else:
                return False, "Could not find insertion point for source block"

    # Insert restore before the final success summary
    # Look for the pattern: # Final summary  OR  echo -e "\n${GREEN}===
    restore_patterns = [
        r'\n# Restore helpful permissions',  # Already has it (shouldn't happen given marker check)
        r'\n# Final summary\n',
        r'\n# Clean up temporary files\n.*?\n\n# Final summary',
        r'\necho -e "\\n\$\{GREEN\}={4,}',
        r'\necho -e "\$\{GREEN\}.*PRIVILEGE ESCALATION',
        r'\necho -e "\$\{GREEN\}.*SUCCESSFUL',
    ]

    restore_inserted = False
    for pattern in restore_patterns:
        if "Restore helpful" in pattern:
            continue
        match = re.search(pattern, new_content, re.DOTALL)
        if match:
            insert_pos = match.start() + 1  # After the \n
            new_content = new_content[:insert_pos] + restore_block + "\n" + new_content[insert_pos:]
            restore_inserted = True
            break

    if not restore_inserted:
        # Fallback: insert before the last "Mark demo as active" or end of file
        mark_pattern = re.search(r'\n# Mark demo as active', new_content)
        if mark_pattern:
            insert_pos = mark_pattern.start() + 1
            new_content = new_content[:insert_pos] + restore_block + "\n" + new_content[insert_pos:]
            restore_inserted = True

    if new_content == content:
        return False, "No changes made"

    if not dry_run:
        with open(path, "w") as f:
            f.write(new_content)

    return True, "Migrated" + ("" if restore_inserted else " (source only, restore not inserted)")


def migrate_cleanup_script(path, dry_run=False):
    """Add safety restore to a cleanup_attack.sh."""
    with open(path) as f:
        content = f.read()

    if RESTORE_MARKER in content:
        return False, "Already migrated"

    depth_prefix = get_depth_prefix(path)

    safety_block = f"""# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/{depth_prefix}/scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

"""

    new_content = content

    # Strategy 1: Insert after "# Configuration" line
    config_match = re.search(r'\n# Configuration\n', new_content)
    if config_match:
        insert_pos = config_match.start() + 1
        new_content = new_content[:insert_pos] + safety_block + new_content[insert_pos:]
    else:
        # Strategy 2: Insert after the color definitions (NC=...)
        nc_match = re.search(r"NC='\\033\[0m'.*?\n\n", new_content, re.DOTALL)
        if nc_match:
            insert_pos = nc_match.end()
            new_content = new_content[:insert_pos] + safety_block + new_content[insert_pos:]
        else:
            # Strategy 3: Insert after the header echo block
            header_match = re.search(r'echo -e "\$\{GREEN\}={4,}\$\{NC\}"\n\n', new_content)
            if header_match:
                insert_pos = header_match.end()
                new_content = new_content[:insert_pos] + safety_block + new_content[insert_pos:]
            else:
                return False, "Could not find insertion point"

    if new_content == content:
        return False, "No changes made"

    if not dry_run:
        with open(path, "w") as f:
            f.write(new_content)

    return True, "Migrated"


def find_scripts(name):
    """Find all scripts of a given name."""
    results = []
    for root, dirs, files in os.walk(SCENARIOS_DIR):
        if name in files:
            results.append(os.path.join(root, name))
    return sorted(results)


def main():
    dry_run = "--dry-run" in sys.argv

    # Migrate demo scripts
    demo_scripts = find_scripts("demo_attack.sh")
    print(f"Found {len(demo_scripts)} demo_attack.sh files")

    demo_migrated = 0
    demo_skipped = 0
    demo_errors = []

    for path in demo_scripts:
        scenario_name = os.path.basename(os.path.dirname(path))
        success, message = migrate_demo_script(path, dry_run)
        if success:
            demo_migrated += 1
            action = "Would migrate" if dry_run else "Migrated"
            print(f"  [OK] {scenario_name}: {action} demo_attack.sh")
        elif "Already" in message:
            demo_skipped += 1
        else:
            demo_errors.append((scenario_name, message))
            print(f"  [ERR] {scenario_name}: {message}")

    print(f"\nDemo scripts: {demo_migrated} migrated, {demo_skipped} skipped, {len(demo_errors)} errors")

    # Migrate cleanup scripts
    cleanup_scripts = find_scripts("cleanup_attack.sh")
    print(f"\nFound {len(cleanup_scripts)} cleanup_attack.sh files")

    cleanup_migrated = 0
    cleanup_skipped = 0
    cleanup_errors = []

    for path in cleanup_scripts:
        scenario_name = os.path.basename(os.path.dirname(path))
        success, message = migrate_cleanup_script(path, dry_run)
        if success:
            cleanup_migrated += 1
            action = "Would migrate" if dry_run else "Migrated"
            print(f"  [OK] {scenario_name}: {action} cleanup_attack.sh")
        elif "Already" in message:
            cleanup_skipped += 1
        else:
            cleanup_errors.append((scenario_name, message))
            print(f"  [ERR] {scenario_name}: {message}")

    print(f"\nCleanup scripts: {cleanup_migrated} migrated, {cleanup_skipped} skipped, {len(cleanup_errors)} errors")

    # Summary
    print(f"\n{'DRY RUN ' if dry_run else ''}SUMMARY:")
    print(f"  Demo scripts migrated:    {demo_migrated}")
    print(f"  Demo scripts skipped:     {demo_skipped}")
    print(f"  Demo script errors:       {len(demo_errors)}")
    print(f"  Cleanup scripts migrated: {cleanup_migrated}")
    print(f"  Cleanup scripts skipped:  {cleanup_skipped}")
    print(f"  Cleanup script errors:    {len(cleanup_errors)}")

    if demo_errors:
        print(f"\nDemo errors:")
        for name, msg in demo_errors:
            print(f"  - {name}: {msg}")
    if cleanup_errors:
        print(f"\nCleanup errors:")
        for name, msg in cleanup_errors:
            print(f"  - {name}: {msg}")


if __name__ == "__main__":
    main()

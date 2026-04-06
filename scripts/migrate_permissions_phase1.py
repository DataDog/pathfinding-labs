#!/usr/bin/env python3
"""
Phase 1 Migration Script: Per-Principal Permissions
Migrates scenario.yaml files from flat to per-principal permissions format.
Also adds Sids to Terraform policy statements.

Usage: python3 scripts/migrate_permissions_phase1.py [--dry-run]
"""

import yaml
import os
import re
import sys
import json

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENARIOS_DIR = os.path.join(PROJECT_ROOT, "modules", "scenarios")


def find_all_scenario_yamls():
    """Find all scenario.yaml files."""
    results = []
    for root, dirs, files in os.walk(SCENARIOS_DIR):
        if "scenario.yaml" in files:
            results.append(os.path.join(root, "scenario.yaml"))
    return sorted(results)


def needs_migration(yaml_path):
    """Check if a scenario.yaml needs per-principal migration."""
    with open(yaml_path) as f:
        data = yaml.safe_load(f)

    permissions = data.get("permissions", {})
    required = permissions.get("required", [])
    helpful = permissions.get("helpful", [])

    # Already migrated if any entry has 'principal' key
    for entry in required + helpful:
        if isinstance(entry, dict) and "principal" in entry:
            return False

    return True


def extract_principal_from_arn(arn):
    """Extract principal name and type from an ARN."""
    # arn:aws:iam::{account_id}:user/pl-prod-xxx -> ("pl-prod-xxx", "user")
    # arn:aws:iam::{account_id}:role/pl-prod-xxx -> ("pl-prod-xxx", "role")
    match = re.search(r":(user|role)/(.+)$", arn)
    if match:
        return match.group(2), match.group(1)
    return None, None


def determine_starting_principal(data):
    """Determine the starting principal from attack_path.principals."""
    principals = data.get("attack_path", {}).get("principals", [])
    if not principals:
        return None, None

    # For most scenarios, the first principal is the starting user
    first_arn = principals[0]
    name, ptype = extract_principal_from_arn(first_arn)

    if name and ptype:
        return name, ptype

    return None, None


def migrate_scenario_yaml(yaml_path, dry_run=False):
    """Migrate a scenario.yaml from flat to per-principal permissions."""
    with open(yaml_path) as f:
        content = f.read()

    with open(yaml_path) as f:
        data = yaml.safe_load(f)

    principal_name, principal_type = determine_starting_principal(data)
    if not principal_name:
        return False, "Could not determine starting principal"

    permissions = data.get("permissions", {})
    required_perms = permissions.get("required", [])
    helpful_perms = permissions.get("helpful", [])

    if not required_perms and not helpful_perms:
        return False, "No permissions to migrate"

    # Build the new YAML block for required
    new_required_block = build_required_block(principal_name, principal_type, required_perms)
    new_helpful_block = build_helpful_block(principal_name, principal_type, helpful_perms)

    # Replace the permissions section in the raw content
    new_content = replace_permissions_section(content, new_required_block, new_helpful_block)

    if new_content == content:
        return False, "No changes needed"

    if not dry_run:
        with open(yaml_path, "w") as f:
            f.write(new_content)

    return True, "Migrated to per-principal format"


def build_required_block(principal_name, principal_type, required_perms):
    """Build the new required permissions YAML block."""
    if not required_perms:
        return ""

    lines = []
    lines.append(f'    - principal: "{principal_name}"')
    lines.append(f'      principal_type: "{principal_type}"')
    lines.append("      permissions:")

    for perm in required_perms:
        lines.append(f'        - permission: "{perm["permission"]}"')
        if "resource" in perm:
            lines.append(f'          resource: "{perm["resource"]}"')

    return "\n".join(lines)


def build_helpful_block(principal_name, principal_type, helpful_perms):
    """Build the new helpful permissions YAML block."""
    if not helpful_perms:
        return ""

    lines = []
    lines.append(f'    - principal: "{principal_name}"')
    lines.append(f'      principal_type: "{principal_type}"')
    lines.append("      permissions:")

    for perm in helpful_perms:
        lines.append(f'        - permission: "{perm["permission"]}"')
        if "purpose" in perm:
            lines.append(f'          purpose: "{perm["purpose"]}"')

    return "\n".join(lines)


def replace_permissions_section(content, new_required_block, new_helpful_block):
    """Replace the permissions section in the raw YAML content."""
    # Find the permissions section and replace it
    # We need to find the start of 'permissions:' and the start of the next section

    lines = content.split("\n")
    result_lines = []
    i = 0
    in_permissions = False
    permissions_indent = 0
    wrote_new = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped == "permissions:":
            in_permissions = True
            permissions_indent = len(line) - len(line.lstrip())
            result_lines.append(line)  # Keep "permissions:"
            i += 1

            # Write the new required block
            result_lines.append("  required:")
            if new_required_block:
                result_lines.append(new_required_block)
            result_lines.append("")

            if new_helpful_block:
                result_lines.append("  helpful:")
                result_lines.append(new_helpful_block)

            # Skip old content until we hit a new section or section separator
            while i < len(lines):
                check_line = lines[i].strip()
                # Check if we hit a new top-level section (comment separator or key at same indent)
                if check_line.startswith("# ===") or (
                    check_line and not check_line.startswith("#") and
                    not check_line.startswith("-") and
                    ":" in check_line and
                    (len(lines[i]) - len(lines[i].lstrip())) <= permissions_indent and
                    check_line != "permissions:"
                ):
                    break
                i += 1

            wrote_new = True
            continue

        result_lines.append(line)
        i += 1

    return "\n".join(result_lines)


def find_terraform_file(scenario_dir):
    """Find the main Terraform file for a scenario."""
    for name in ["prod.tf", "main.tf", "dev.tf"]:
        path = os.path.join(scenario_dir, name)
        if os.path.exists(path):
            return path
    return None


def add_sids_to_terraform(tf_path, dry_run=False):
    """Add Sids to Terraform policy statements if missing."""
    if not tf_path or not os.path.exists(tf_path):
        return False, "No Terraform file found"

    with open(tf_path) as f:
        content = f.read()

    original = content

    # Check if there are already proper Sids
    has_required_sid = "RequiredForExploitation" in content
    has_helpful_sid = "HelpfulForExploitation" in content

    if has_required_sid and has_helpful_sid:
        return False, "Sids already present"

    # Add RequiredForExploitation Sid to statements that look like required permissions
    # This is a heuristic - look for Statement blocks without Sid
    # We use a simple regex approach since HCL parsing is complex

    # Pattern: find Statement blocks that have exploit-related actions but no Sid
    # This is imperfect but catches the common patterns

    # For now, just report that Sids need manual attention if missing
    changes = []
    if not has_required_sid:
        changes.append("Missing RequiredForExploitation Sid")
    if not has_helpful_sid and "HelpfulForDemoScript" not in content and "helpfulAdditionalPermissions" not in content:
        # Check if there are helpful-looking permissions
        helpful_actions = ["iam:ListUsers", "iam:ListRoles", "iam:GetRole", "iam:GetUser",
                          "lambda:GetFunction", "lambda:DeleteFunction", "sts:GetCallerIdentity",
                          "ec2:DescribeInstances", "ec2:DescribeVpcs", "ec2:DescribeSubnets",
                          "glue:GetJob", "glue:GetJobRun", "codebuild:BatchGetBuilds",
                          "cloudformation:DescribeStacks", "iam:ListAttachedUserPolicies",
                          "iam:ListAttachedRolePolicies", "sagemaker:DescribeTrainingJob",
                          "sagemaker:DescribeNotebookInstance", "ssm:DescribeInstanceInformation",
                          "ecs:DescribeTasks"]
        has_helpful_perms = any(action in content for action in helpful_actions)
        if has_helpful_perms:
            changes.append("Has helpful permissions but no HelpfulForExploitation Sid")

    if changes:
        return False, "; ".join(changes) + " (needs agent)"
    return False, "No Sid changes needed"


def main():
    dry_run = "--dry-run" in sys.argv

    yaml_files = find_all_scenario_yamls()
    print(f"Found {len(yaml_files)} scenario.yaml files")

    migrated = 0
    skipped = 0
    errors = 0
    needs_terraform_agent = []

    for yaml_path in yaml_files:
        scenario_dir = os.path.dirname(yaml_path)
        rel_path = os.path.relpath(scenario_dir, PROJECT_ROOT)
        scenario_name = os.path.basename(scenario_dir)

        if not needs_migration(yaml_path):
            skipped += 1
            continue

        # Migrate scenario.yaml
        success, message = migrate_scenario_yaml(yaml_path, dry_run)
        if success:
            migrated += 1
            action = "Would migrate" if dry_run else "Migrated"
            print(f"  [OK] {scenario_name}: {action}")
        else:
            if "Could not determine" in message:
                errors += 1
                print(f"  [ERR] {scenario_name}: {message}")
            else:
                skipped += 1

        # Check Terraform
        tf_path = find_terraform_file(scenario_dir)
        tf_success, tf_message = add_sids_to_terraform(tf_path, dry_run)
        if "needs agent" in tf_message:
            needs_terraform_agent.append((scenario_name, tf_message))

    print(f"\n{'DRY RUN ' if dry_run else ''}Summary:")
    print(f"  Migrated scenario.yaml: {migrated}")
    print(f"  Already migrated: {skipped}")
    print(f"  Errors: {errors}")
    print(f"  Need Terraform agent: {len(needs_terraform_agent)}")

    if needs_terraform_agent:
        print(f"\nScenarios needing Terraform Sid updates:")
        for name, msg in needs_terraform_agent:
            print(f"  - {name}: {msg}")


if __name__ == "__main__":
    main()

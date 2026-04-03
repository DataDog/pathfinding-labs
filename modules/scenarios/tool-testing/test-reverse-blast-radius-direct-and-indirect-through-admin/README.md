# Reverse Blast Radius: Direct and Indirect S3 Access Through Admin

* **Category:** Tool Testing
* **Sub-Category:** reverse-blast-radius
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Validating security tool detection of both direct and indirect S3 bucket access via administrative permissions
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin`
* **Schema Version:** 4.0.0
* **MITRE Tactics:** TA0009 - Collection, TA0004 - Privilege Escalation
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a tool testing scenario that validates whether security tools correctly identify both `pl-prod-rbr-admin-user1` (with explicit S3 permissions) and `pl-prod-rbr-admin-user2` (with indirect access via `pl-prod-rbr-admin-role3`, which holds AdministratorAccess) as principals capable of reading objects from the `pl-sensitive-data-rbr-admin-{account_id}-{suffix}` S3 bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-admin-user1` (direct path) / `arn:aws:iam::{account_id}:user/pl-prod-rbr-admin-user2` (indirect path)
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-admin-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-admin-user1`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-admin-*/*` -- explicit permission to read objects from the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-admin-*` -- explicit permission to list the target bucket

**Required** (`pl-prod-rbr-admin-user2`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-admin-role3` -- can assume the administrative role

**Required** (`pl-prod-rbr-admin-role3`):
- `*` on `*` -- AdministratorAccess policy grants implicit access to all resources including the target S3 bucket

**Helpful** (`pl-prod-rbr-admin-user1`):
- `sts:GetCallerIdentity` -- verify current identity
- `s3:ListAllMyBuckets` -- discover available buckets

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-admin-user1` | User with direct S3 access permissions and access keys |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-admin-user2` | User with permission to assume administrative role and access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-admin-role3` | Administrative role with AdministratorAccess managed policy |
| `arn:aws:iam::{account_id}:policy/pl-prod-rbr-admin-user1-s3-policy` | Policy granting direct S3 access to user1 |
| `arn:aws:iam::{account_id}:policy/pl-prod-rbr-admin-user2-assume-policy` | Policy granting user2 permission to assume role3 |
| `arn:aws:s3:::pl-sensitive-data-rbr-admin-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Demonstrate Path 1: Direct access using user1 credentials
3. Demonstrate Path 2: Indirect access via admin role using user2 credentials
4. Show the commands being executed and their results
5. Verify that both paths successfully access the same S3 bucket
6. Output standardized test results for automation

#### Resources Created by Attack Script

- Temporary test objects uploaded to the S3 bucket during path demonstrations

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-direct-and-indirect-through-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This is a tool testing scenario focused on configuration analysis rather than runtime exploitation. The infrastructure remains in place for testing. The cleanup script will remove any temporary test objects created in the S3 bucket during demonstrations, but preserves the core infrastructure for continued security tool testing.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-direct-and-indirect-through-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

When performing reverse blast radius analysis on the sensitive S3 bucket (`pl-sensitive-data-rbr-admin-*`), security tools should identify:

1. **Direct Access Path**:
   - `pl-prod-rbr-admin-user1` has explicit S3 permissions
   - Policy grants `s3:ListAllMyBuckets`, `s3:ListBucket`, and `s3:GetObject` on the bucket
   - This is typically what most tools successfully detect

2. **Indirect Access Path (Critical Test)**:
   - `pl-prod-rbr-admin-user2` has access via administrative role assumption
   - User2 can assume `pl-prod-rbr-admin-role3`
   - Role3 has AdministratorAccess policy (`*:*` on all resources)
   - Therefore, user2 has implicit access to the S3 bucket
   - **Many tools fail to detect this indirect administrative access path**

3. **Administrative Permission Analysis**:
   - Any principal with `*:*` permissions should be flagged as having access to ALL resources
   - Tools should recognize that AdministratorAccess grants S3 bucket access
   - This applies to both IAM roles and users with administrative policies

4. **Role Assumption Chain**:
   - Tools should traverse role assumption relationships
   - If UserA can assume RoleB, and RoleB has access to ResourceC, then UserA effectively has access to ResourceC

Use this scenario to test if your security tools can:
- [ ] Identify user1 as having direct access to the bucket
- [ ] Identify user2 as having indirect access via role assumption
- [ ] Recognize that AdministratorAccess policy grants access to all S3 buckets
- [ ] Traverse multi-step access paths (user → role → resource)
- [ ] Answer "who has access to this bucket?" with both direct and indirect principals
- [ ] Differentiate between explicit S3 permissions and implicit administrative access
- [ ] Report administrative privileges as a security risk for sensitive resource access

If your security tooling identifies only user1 (direct access) but misses user2 (administrative access), you have a significant gap in your security visibility that could impact incident response, access reviews, and compliance reporting.

#### Prevention Recommendations

- Minimize the use of AdministratorAccess and other highly privileged managed policies — they create implicit access to all resources that's difficult to track
- Implement principle of least privilege with specific, scoped permissions rather than broad administrative access
- Use IAM Access Analyzer to identify all principals with access to sensitive S3 buckets, including those with administrative permissions
- Regularly audit role assumption permissions and trust relationships to understand privilege escalation paths
- Implement resource-based policies on S3 buckets to add additional access controls beyond IAM policies
- Use AWS Organizations SCPs to prevent creation of overly permissive administrative policies at scale
- Enable CloudTrail logging and monitor for role assumption events (`AssumeRole`) to high-privilege roles
- Tag sensitive S3 buckets and implement automated scanning to identify all principals with access (direct or indirect)
- Consider using AWS IAM Access Analyzer's policy validation to assess permissions before deployment
- Implement break-glass procedures for administrative access that require additional authentication and are time-limited
- Use session policies when assuming administrative roles to scope down permissions to only what's needed for the task

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` — Role assumption by user2 to the administrative role; critical when the target role has AdministratorAccess or broad permissions
- `S3: GetObject` — Object retrieval from the sensitive bucket; monitor for access by principals that should not have direct S3 permissions
- `S3: ListBucket` — Bucket enumeration on the sensitive bucket; indicates a principal is discovering bucket contents
- `IAM: GetUser` — Identity enumeration; often precedes escalation or access attempts

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

# Direct and Indirect Access Paths to Bucket

* **Category:** Tool Testing
* **Sub-Category:** reverse-blast-radius
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Testing security tool capability to identify both direct and indirect S3 bucket access paths in reverse blast radius queries
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket`
* **Schema Version:** 4.1.1
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool can detect both direct and indirect S3 bucket access by demonstrating that `pl-prod-rbr-di-user1` can access the `pl-sensitive-data-rbr-di-{account_id}-{suffix}` bucket directly via IAM permissions, while `pl-prod-rbr-di-user2` can access the same bucket indirectly by assuming `pl-prod-rbr-di-role3` which holds the S3 permissions.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user1` (direct path) and `arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user2` (indirect path)
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-di-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-di-user1`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-di-*/*` -- direct permission to read objects from the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-di-*` -- direct permission to list the target bucket

**Required** (`pl-prod-rbr-di-user2`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-di-role3` -- can assume role3 to gain indirect bucket access

**Required** (`pl-prod-rbr-di-role3`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-di-*/*` -- permission to read objects from the target bucket (inherited by user2 via role assumption)
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-di-*` -- permission to list the target bucket (inherited by user2 via role assumption)

**Helpful** (`pl-prod-rbr-di-user1`):
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
plabs enable test-reverse-blast-radius-direct-and-indirect-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-direct-and-indirect-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user1` | User with direct S3 bucket access permissions (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user2` | User with sts:AssumeRole permission for role3 (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-di-role3` | Role with S3 bucket access, assumable by user2 |
| `arn:aws:s3:::pl-sensitive-data-rbr-di-{account_id}-{suffix}` | Target sensitive S3 bucket containing test data |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials and bucket name from Terraform outputs
2. Verify user1's identity and demonstrate direct S3 bucket access (list and download objects)
3. Verify user2's identity and confirm that user2 lacks direct bucket access
4. Assume `pl-prod-rbr-di-role3` using user2's credentials
5. Demonstrate indirect bucket access via the assumed role (list and download objects)
6. Print a summary showing both access paths and the reverse blast radius test result

#### Resources Created by Attack Script

- `/tmp/sensitive-user1.txt` -- object downloaded from the sensitive bucket using user1's direct credentials
- `/tmp/sensitive-role3.txt` -- object downloaded from the sensitive bucket using role3's assumed credentials

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-direct-and-indirect-to-bucket
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-direct-and-indirect-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-direct-and-indirect-to-bucket
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-direct-and-indirect-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-direct-and-indirect-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-direct-and-indirect-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A properly configured security analysis platform or CSPM tool performing a reverse blast radius query on the S3 bucket should identify:

1. **Direct Access Path**: `pl-prod-rbr-di-user1` has direct access to the bucket through IAM permissions
2. **Indirect Access Path**: `pl-prod-rbr-di-user2` has indirect access to the bucket through role assumption (`user2` → `role3` → `bucket`)
3. **Complete Access List**: When asked "Who has access to bucket pl-sensitive-data-rbr-di-*?", the tool should return BOTH users in the result set

**Expected Query Results:**

Query: "Who can access bucket `pl-sensitive-data-rbr-di-{account_id}-{suffix}`?"

Expected Response:
```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user1 (direct access)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user2 (indirect via role/pl-prod-rbr-di-role3)
- arn:aws:iam::{account_id}:role/pl-prod-rbr-di-role3 (direct access)
```

**Tool Testing Focus:**

This scenario specifically tests:

1. **Graph Traversal Capability**: Can the tool traverse IAM trust relationships to identify indirect access?
2. **Complete Path Enumeration**: Does the tool identify ALL principals with access, not just those with direct permissions?
3. **Role Assumption Detection**: Can the tool recognize that users who can assume roles inherit those roles' permissions?
4. **Reverse Query Accuracy**: When querying "who has access to X", does the tool return complete results?

**Expected Tool Behavior:**

Passing tools:
- Identify both user1 (direct) and user2 (indirect) as having bucket access
- Show the complete path: user2 → role3 → bucket
- Provide clear indication of direct vs. indirect access
- Include role3 itself as a principal with access

Failing tools:
- Only identify user1 (direct access)
- Only identify role3 but miss user2
- Fail to traverse the AssumeRole trust relationship
- Provide incomplete results for "who has access" queries

#### Prevention Recommendations

While this is a tool-testing scenario designed to validate detection capabilities rather than demonstrate a real vulnerability, the following best practices apply to managing S3 bucket access in production environments:

- Use AWS IAM Access Analyzer to continuously monitor and validate S3 bucket access permissions
- Implement least privilege principles - grant S3 access only to principals that require it
- Regularly audit IAM trust relationships to understand complete access paths to sensitive resources
- Use S3 bucket policies in addition to IAM policies to implement defense in depth
- Monitor CloudTrail for S3 access patterns from unexpected principals or roles
- Implement SCPs (Service Control Policies) at the organization level to prevent overly broad S3 permissions
- Use tools that support reverse blast radius queries to understand "who can access X" for critical resources
- Regularly validate that your security tooling can identify both direct and indirect access paths
- Consider implementing resource-based conditions that restrict access even when IAM permissions allow it
- Use AWS Config rules to detect and alert on changes to S3 bucket permissions or IAM trust policies

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Role assumption by user2 to gain indirect S3 bucket access; monitor for assumption of `pl-prod-rbr-di-role3`
- `S3: GetObject` -- Object retrieval from the sensitive bucket; monitor for access by unexpected principals or assumed-role sessions
- `S3: ListBucket` -- Bucket listing requests; monitor for enumeration of bucket contents from both direct and indirect principals

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

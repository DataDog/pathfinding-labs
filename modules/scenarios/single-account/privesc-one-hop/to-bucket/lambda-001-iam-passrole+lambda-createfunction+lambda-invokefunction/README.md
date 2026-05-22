# Lambda Function Creation + Invocation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:PassRole, lambda:CreateFunction, and lambda:InvokeFunction can access an S3 bucket by creating a Lambda with the bucket-access role and invoking it to read the flag
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-001
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-001-to-bucket-starting-user` IAM user to the `pl-prod-lambda-001-to-bucket-{account_id}-{suffix}` S3 bucket by creating a Lambda function with the target role as its execution role and invoking it to read the flag directly from the bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-001-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-001-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-001-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-001-to-bucket-target-role` -- allows associating the bucket-access role as the Lambda execution role
- `lambda:CreateFunction` on `*` -- allows creating a new Lambda function
- `lambda:InvokeFunction` on `*` -- allows invoking the Lambda function to read from the bucket

**Helpful** (`pl-prod-lambda-001-to-bucket-starting-user`):
- `iam:ListRoles` -- discover available roles that can be passed to Lambda
- `lambda:GetFunction` -- verify function creation succeeded before invoking
- `lambda:DeleteFunction` -- clean up attack artifacts after flag retrieval

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-001-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-001-to-bucket-starting-user` | Starting principal with PassRole, CreateFunction, and InvokeFunction permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-001-to-bucket-target-role` | Target role with s3:GetObject and s3:ListBucket on the target bucket |
| `arn:aws:s3:::pl-prod-lambda-001-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing the CTF flag |
| `arn:aws:s3:::pl-prod-lambda-001-to-bucket-{account_id}-{suffix}/flag.txt` | CTF flag object inside the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-001-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access
4. Create a Lambda deployment package containing a handler that reads the flag from the target bucket
5. Create a Lambda function named `pl-lambda-001-to-bucket-extractor` with the target role as its execution role
6. Wait for the function to reach Active state
7. Invoke the Lambda function and parse the flag from the response body

#### Resources Created by Attack Script

- A temporary Lambda function (`pl-lambda-001-to-bucket-extractor`) created with the bucket-access execution role

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-001-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-001-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-lambda-001-to-bucket-starting-user`) has `iam:PassRole` permission allowing it to pass the bucket-access role (`pl-prod-lambda-001-to-bucket-target-role`) to Lambda
- IAM user has `lambda:CreateFunction` and `lambda:InvokeFunction` permissions, enabling it to create and trigger functions under a role it cannot directly assume
- Privilege escalation path exists: starting user can read from the target S3 bucket via a transiently created Lambda function without ever directly holding `s3:GetObject`
- No `iam:PassedToService` condition restricts what services the role may be passed to

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which AWS services a role can be passed to
- Avoid granting `lambda:CreateFunction` to users who also hold `iam:PassRole` on any role with data-access permissions
- Implement SCPs that prevent passing roles with S3 access to Lambda unless the combination is explicitly approved
- Use IAM Access Analyzer to surface privilege escalation paths that traverse PassRole and compute service creation
- Apply resource-level conditions on `lambda:CreateFunction` to restrict function creation to approved naming prefixes or resource tags
- Enable AWS Config rules to alert when Lambda functions are created with roles that have sensitive data permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:CreateFunction20150331` -- new Lambda function created; inspect `requestParameters.role` in the event for the role ARN being passed — a role with S3 access passed here is the PassRole signal; high severity when the role grants data access
- `lambda:InvokeFunction` -- Lambda function invoked; high severity when the function was recently created and uses a role with S3 permissions
- `s3:GetObject` -- S3 object retrieved using Lambda execution role credentials; high severity when the IAM principal is an assumed-role session for the bucket-access role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Lambda Function Creation + Invocation to Admin](https://pathfinding.cloud/paths/lambda-001) -- companion to-admin version of this same PassRole technique
- [T1648 - Serverless Execution](https://attack.mitre.org/techniques/T1648/) -- MITRE ATT&CK technique page
- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique page

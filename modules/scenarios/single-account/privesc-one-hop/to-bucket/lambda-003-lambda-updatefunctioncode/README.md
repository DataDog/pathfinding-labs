# Lambda Function Code Update to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying existing Lambda function code to execute malicious logic under privileged execution role with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_003_lambda_updatefunctioncode`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-003
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1525 - Implant Internal Image

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-003-to-bucket-starting-user` IAM user to the `pl-prod-lambda-003-to-bucket-{account_id}-{resource_suffix}` S3 bucket by updating an existing Lambda function's code with a malicious payload that reads the target bucket's contents and returns them in the function response, then invoking it under the function's privileged execution role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-003-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-003-to-bucket-{account_id}-{resource_suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-003-to-bucket-starting-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-lambda-003-to-bucket-target-lambda` -- replace existing Lambda function code with a malicious payload
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-lambda-003-to-bucket-target-lambda` -- trigger execution of the malicious payload under the function's S3-privileged role

**Helpful** (`pl-prod-lambda-003-to-bucket-starting-user`):
- `lambda:GetFunction` -- discover Lambda function details including handler name and execution role
- `lambda:ListFunctions` -- discover available Lambda functions to target
- `iam:GetRole` -- view Lambda execution role permissions to identify functions with S3 access

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-003-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-003-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-003-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-lambda-003-to-bucket-target-lambda` | Pre-existing Lambda function that runs benign code (victim workload) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-003-to-bucket-target-role` | Lambda execution role with s3:GetObject and s3:ListBucket on the target bucket |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-003-to-bucket-starting-user` (inline policy `pl-prod-lambda-003-to-bucket-starting-user-policy`) | Grants starting user lambda:UpdateFunctionCode and lambda:InvokeFunction |
| `arn:aws:s3:::pl-prod-lambda-003-to-bucket-{account_id}-{resource_suffix}` | Target S3 bucket containing the CTF flag |
| `arn:aws:s3:::pl-prod-lambda-003-to-bucket-{account_id}-{resource_suffix}/flag.txt` | CTF flag stored as an S3 object; readable via the Lambda execution role |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-003-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access
4. Download the existing Lambda function code and inspect the handler name
5. Create a malicious payload that reads `flag.txt` from the target bucket (using the `TARGET_BUCKET` env var already set on the function) and returns the contents in the response
6. Deploy the updated code with `lambda:UpdateFunctionCode`
7. Invoke the Lambda function and extract the flag value from the response body

#### Resources Created by Attack Script

- Downloaded backup of original Lambda deployment package (`/tmp/original_lambda_backup.zip`)
- Malicious Lambda deployment package (`/tmp/lambda_function.zip`)
- Modified Lambda function code on `pl-prod-lambda-003-to-bucket-target-lambda` (restored by cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-003-lambda-updatefunctioncode
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-003-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-003-lambda-updatefunctioncode
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-003-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-003-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-003-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-lambda-003-to-bucket-starting-user`) has `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on a Lambda function whose execution role holds S3 read access to a sensitive bucket
- Privilege escalation path: the starting user can reach the contents of `pl-prod-lambda-003-to-bucket-{account_id}` by injecting code into a function that already has bucket access
- Lambda function lacks code signing enforcement, allowing arbitrary code replacement without authorization gates
- Lambda execution role (`pl-prod-lambda-003-to-bucket-target-role`) grants `s3:GetObject` and `s3:ListBucket` on the target bucket without restricting which code paths can exercise those permissions

#### Prevention Recommendations

- **Implement Code Signing**: Require Lambda functions to use code signing to prevent unauthorized code modifications; unsigned deployments should be rejected at the API level
- **Restrict Update Permissions**: Limit `lambda:UpdateFunctionCode` to dedicated CI/CD roles with strict resource conditions; never grant it to user accounts directly
- **Apply Least Privilege to Execution Roles**: Lambda execution roles should only have permissions required for their specific business function; an execution role should never have `s3:GetObject` on buckets it does not need to read
- **Use Resource Conditions**: Apply resource-based IAM conditions so that execution-role S3 access is scoped to specific bucket key prefixes and cannot be leveraged by arbitrary injected code
- **Implement SCPs**: Use Service Control Policies to prevent ad-hoc code updates on Lambda functions tagged as production workloads
- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to surface privilege escalation paths that combine `lambda:UpdateFunctionCode` with functions that hold sensitive bucket access
- **Separate Deployment and Runtime Roles**: Use separate AWS accounts or strict permission boundaries to isolate code deployment infrastructure from production S3 data

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when the target function's execution role holds S3 read access
- `lambda:Invoke` -- Lambda function invoked; correlate with a preceding `UpdateFunctionCode` event to detect malicious payload execution against a sensitive function
- `s3:GetObject` -- Object retrieved from S3 bucket by the Lambda execution role; critical when preceded by an unusual code update from a non-deployment principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [lambda-003 on pathfinding.cloud](https://pathfinding.cloud/paths/lambda-003) -- Canonical technique documentation for Lambda UpdateFunctionCode privilege escalation
- [T1525 - Implant Internal Image](https://attack.mitre.org/techniques/T1525/) -- MITRE ATT&CK technique page for implanting code into existing workloads
- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique page for data collection from cloud storage

# Lambda Code Update + Invocation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying existing Lambda function code and manually invoking it to execute malicious logic under privileged execution role to read S3 bucket contents
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_004_lambda_updatefunctioncode_lambda_invokefunction`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-004
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1525 - Implant Internal Image

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-004-to-bucket-starting-user` IAM user to the `pl-prod-lambda-004-to-bucket-target-role` execution role (and subsequently the `pl-prod-lambda-004-to-bucket-{account_id}-{suffix}` S3 bucket) by modifying existing Lambda function code with a malicious payload and immediately invoking it to execute arbitrary operations under the function's privileged execution role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-004-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-004-to-bucket-starting-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-lambda-004-to-bucket-target-lambda` -- replace the existing Lambda function code with a malicious payload
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-lambda-004-to-bucket-target-lambda` -- immediately trigger execution of the malicious payload under the function's privileged role

**Helpful** (`pl-prod-lambda-004-to-bucket-starting-user`):
- `lambda:GetFunction` -- discover Lambda function details including handler name and execution role
- `lambda:ListFunctions` -- discover available Lambda functions to target
- `iam:GetRole` -- view Lambda execution role permissions to identify S3 access

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-004-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-004-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-lambda-004-to-bucket-target-lambda` | Pre-existing Lambda function that runs benign code (victim workload) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-004-to-bucket-target-role` | Lambda execution role with s3:GetObject and s3:ListBucket on the target bucket |
| `arn:aws:s3:::pl-prod-lambda-004-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing the CTF flag |
| `arn:aws:s3:::pl-prod-lambda-004-to-bucket-{account_id}-{suffix}/flag.txt` | CTF flag object inside the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-004-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access
4. Retrieve the target Lambda function's current configuration (handler name, execution role)
5. Create a replacement handler that reads `flag.txt` from the bucket (bucket name embedded in the payload)
6. Package and deploy the modified code with `lambda:UpdateFunctionCode`
7. Invoke the function with `lambda:InvokeFunction` and capture the response body
8. Extract `flag.txt` contents returned by the Lambda execution
9. Restore the original function code

#### Resources Created by Attack Script

- Modified Lambda deployment package (zip file) with attacker-appended code
- Downloaded original Lambda code zip (restored during cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-004-lambda-updatefunctioncode+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-004-lambda-updatefunctioncode+lambda-invokefunction
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-004-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-004-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Users or roles with `lambda:UpdateFunctionCode` on Lambda functions whose execution roles have S3 read access to sensitive buckets
- Users or roles with both `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` on the same Lambda function — this combination allows immediate, on-demand execution of arbitrary code under the function's role
- Lambda execution roles (`pl-prod-lambda-004-to-bucket-target-role`) with `s3:GetObject` or `s3:ListBucket` on sensitive buckets, paired with functions whose code can be modified by external principals
- Lambda functions without code signing enforcement, allowing arbitrary code injection
- The absence of resource-based conditions on `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` that would restrict which principals can modify and invoke high-privilege functions

#### Prevention Recommendations

- **Implement Code Signing**: Require Lambda functions to use code signing configurations to prevent unauthorized code modifications
- **Apply Least Privilege to Execution Roles**: Lambda execution roles should have only the S3 permissions required for their specific business function, scoped to specific bucket ARNs and key prefixes
- **Separate Update and Invoke Permissions**: Never grant both `lambda:UpdateFunctionCode` and `lambda:InvokeFunction` to the same principal for functions with sensitive execution roles
- **Restrict Update Permissions to CI/CD Identities**: Limit `lambda:UpdateFunctionCode` to dedicated deployment pipeline roles with strict IAM conditions (`aws:CalledVia`, source IP, MFA)
- **Use Resource Conditions**: Apply resource-based IAM conditions to restrict which Lambda functions can be modified and invoked by which principals
- **IAM Access Analyzer**: Use AWS IAM Access Analyzer to surface privilege escalation paths that combine Lambda code update permissions with sensitive execution roles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when followed by an invocation of the same function, especially when the execution role has S3 read access
- `lambda:Invoke` -- Lambda function invoked; correlate with recent UpdateFunctionCode events on the same function to detect attacker-controlled execution sequences
- `s3:GetObject` -- Object retrieved from S3 bucket; high severity when the caller is a Lambda execution role and the call immediately follows a code update event

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [lambda-004 on pathfinding.cloud](https://pathfinding.cloud/paths/lambda-004) -- Lambda UpdateFunctionCode + InvokeFunction privilege escalation technique details
- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique for collecting data from cloud storage
- [T1525 - Implant Internal Image](https://attack.mitre.org/techniques/T1525/) -- MITRE ATT&CK technique for implanting malicious code in existing workloads

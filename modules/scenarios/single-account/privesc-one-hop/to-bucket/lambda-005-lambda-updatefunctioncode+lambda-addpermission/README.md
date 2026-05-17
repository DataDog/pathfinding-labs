# Lambda Code Update + Permission Grant to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with lambda:UpdateFunctionCode and lambda:AddPermission can modify existing Lambda function code, grant themselves invoke permission, and read sensitive S3 bucket contents using the function's privileged role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_005_lambda_updatefunctioncode_lambda_addpermission`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-005
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-005-to-bucket-starting-user` IAM user to the `pl-prod-lambda-005-to-bucket-{account_id}-{suffix}` S3 bucket by modifying an existing Lambda function's code with a payload that reads the flag, granting yourself invocation rights via a resource-based policy, and executing the function to extract the flag from the bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-005-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-005-to-bucket-starting-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-bucket-target-lambda` -- replace existing function code with a payload that reads from the target S3 bucket
- `lambda:AddPermission` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-bucket-target-lambda` -- add a resource-based policy statement granting self-invocation
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-bucket-target-lambda` -- trigger execution of the malicious payload under the privileged role

**Helpful** (`pl-prod-lambda-005-to-bucket-starting-user`):
- `lambda:GetFunction` -- discover the target Lambda function's execution role ARN and handler name
- `lambda:GetPolicy` -- verify the resource-based policy statement was successfully added
- `lambda:ListFunctions` -- enumerate available Lambda functions to identify high-privilege targets

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-005-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-005-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-lambda-005-to-bucket-target-lambda` | Pre-existing Lambda function that runs benign code (victim workload) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-005-to-bucket-lambda-exec-role` | Lambda execution role with S3 read access to the target bucket |
| `arn:aws:s3:::pl-prod-lambda-005-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing the CTF flag (`flag.txt`) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-005-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access
4. Fetch the existing Lambda configuration (handler name and execution role ARN)
5. Craft a malicious payload that reads `flag.txt` from the target S3 bucket and returns it in the response
6. Update the Lambda function code with the malicious payload
7. Add a resource-based policy statement granting self-invocation via `lambda:AddPermission`
8. Invoke the modified Lambda function and extract the flag from the response body

#### Resources Created by Attack Script

- Resource-based policy statement on the target Lambda function granting the starting user `lambda:InvokeFunction`
- Modified Lambda function code in `pl-prod-lambda-005-to-bucket-target-lambda` (replaced with S3-reading payload)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-005-lambda-updatefunctioncode+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-005-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-005-lambda-updatefunctioncode+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-005-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-005-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-005-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Overly Permissive Lambda Update Access**: IAM principals with `lambda:UpdateFunctionCode` on Lambda functions whose execution roles have S3 read access
- **Lambda Functions with Scoped S3 Access**: Lambda execution roles that grant `s3:GetObject` on buckets containing sensitive data, combined with code update permissions on the function
- **Resource Policy Modification Access**: Principals with `lambda:AddPermission` on privileged Lambda functions can bypass resource-based policy protections intended to restrict invocation
- **Privilege Escalation Path**: The combination of `lambda:UpdateFunctionCode`, `lambda:AddPermission`, and `lambda:InvokeFunction` on a function with an S3-capable execution role creates a complete data exfiltration path
- **Lack of Code Signing**: Lambda functions without code signing enforcement allow arbitrary code to be injected and run under the execution role's identity
- **Missing Resource Conditions**: Lambda update policies lacking resource-based conditions that restrict which functions or callers are eligible

#### Prevention Recommendations

- **Implement Code Signing**: Require Lambda functions with privileged execution roles to use code signing, preventing unauthorized code modifications
- **Apply Least Privilege to Execution Roles**: Lambda execution roles should have `s3:GetObject` scoped to only the specific bucket paths required, never broad S3 access
- **Restrict Update Permissions**: Limit `lambda:UpdateFunctionCode` to dedicated CI/CD service roles with strict condition keys (`lambda:FunctionArn`, `aws:RequestedRegion`)
- **Protect Resource Policies**: Deny `lambda:AddPermission` for general-purpose roles via SCPs or permission boundaries; only allow it from deployment pipeline identities
- **Separate Deployment and Data Access**: Use separate IAM roles for deploying Lambda functions and for those functions' runtime access to sensitive data stores
- **Enable CloudTrail Monitoring**: Alert on `UpdateFunctionCode20150331v2`, `AddPermission20150331v2`, and `Invoke` events on functions with S3-capable execution roles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when the target function's execution role has S3 read/write access
- `lambda:AddPermission20150331v2` -- Resource-based policy statement added to a Lambda function; indicates an attacker may be granting themselves invocation rights on a privileged function
- `lambda:Invoke` -- Lambda function invoked; high severity when preceded by a code update and permission addition on a function with an S3-capable execution role
- `s3:GetObject` -- Object retrieved from S3 bucket; high severity when the request comes from a Lambda execution role following an unexpected code update

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Lambda Code Update + Permission Grant to Admin (lambda-005)](https://pathfinding.cloud/paths/lambda-005) -- pathfinding.cloud path entry for the lambda-005 technique
- [T1648 - Serverless Execution](https://attack.mitre.org/techniques/T1648/) -- MITRE ATT&CK technique for abusing serverless execution environments
- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique for accessing cloud storage data

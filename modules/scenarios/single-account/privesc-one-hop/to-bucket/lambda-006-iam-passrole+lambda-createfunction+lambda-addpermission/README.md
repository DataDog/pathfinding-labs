# Lambda Function Creation + Permission Grant to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:PassRole, lambda:CreateFunction, and lambda:AddPermission can create a new Lambda function with an S3-scoped role, add permission to invoke it, and execute code that reads the target bucket's flag
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-006
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-006-to-bucket-starting-user` IAM user to the `pl-prod-lambda-006-to-bucket-{account_id}-{suffix}` S3 bucket by creating a malicious Lambda function with the target role as its execution role, granting yourself invocation rights via `lambda:AddPermission`, and invoking the function to read `flag.txt` from the bucket and return it in the response.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-006-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-006-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-006-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-006-to-bucket-target-role` -- allows assigning the S3-scoped role as the Lambda execution role
- `lambda:CreateFunction` on `*` -- allows creating a new Lambda function
- `lambda:AddPermission` on `*` -- allows adding a resource-based policy granting invocation rights
- `lambda:InvokeFunction` on `*` -- allows invoking the Lambda function once permissions are set

**Helpful** (`pl-prod-lambda-006-to-bucket-starting-user`):
- `iam:ListRoles` -- discover available roles and their attached policies
- `lambda:GetFunction` -- verify function creation and retrieve details
- `lambda:GetPolicy` -- verify the resource-based policy was added
- `lambda:DeleteFunction` -- clean up the malicious function after the attack

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-006-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-006-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-006-to-bucket-target-role` | Execution role with s3:GetObject and s3:ListBucket on the target bucket |
| `arn:aws:s3:::pl-prod-lambda-006-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing the CTF flag |
| `arn:aws:s3:::pl-prod-lambda-006-to-bucket-{account_id}-{suffix}/flag.txt` | CTF flag object inside the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-006-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access to the target bucket
4. Create a Lambda function payload that reads `flag.txt` and returns it in the response
5. Create the Lambda function with `pl-prod-lambda-006-to-bucket-target-role` as the execution role
6. Add a resource-based policy granting the starting user invocation rights via `lambda:AddPermission`
7. Wait for the function to reach Active state
8. Invoke the Lambda function and extract `flag.txt` contents from the response

#### Resources Created by Attack Script

- A malicious Lambda function (`pl-lambda-006-to-bucket-escalation`) with the target role as its execution role
- A resource-based policy statement on the Lambda function granting the starting user invocation rights

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-006-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-006-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-lambda-006-to-bucket-starting-user`) has `iam:PassRole` permission targeting a role with S3 read access to a sensitive bucket
- IAM user has `lambda:CreateFunction` permission allowing creation of functions with privileged execution roles
- IAM user has `lambda:AddPermission` allowing modification of Lambda resource-based policies to self-grant invocation rights
- Privilege escalation path detected: user can combine PassRole + CreateFunction + AddPermission + InvokeFunction to read data from the target S3 bucket without holding direct S3 permissions
- Lambda execution role `pl-prod-lambda-006-to-bucket-target-role` grants bucket read access and is passable by a principal that also controls Lambda creation

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit PassRole specifically to approved services; pair it with strict resource conditions so only non-sensitive roles can be passed
- Avoid co-locating `lambda:CreateFunction` and `lambda:AddPermission` in the same policy; separation of duties prevents the full exploit chain
- Implement Service Control Policies (SCPs) that prevent passing roles with data-access permissions to Lambda functions
- Require Lambda execution roles to be created from approved templates with scoped-down permissions, enforced via an AWS Config or IAM Access Analyzer policy check
- Use IAM Access Analyzer to identify privilege escalation paths where a principal can reach sensitive data indirectly via PassRole and Lambda
- Enable S3 access logging and set alerts on `GetObject` calls from Lambda execution role ARNs that are unusual or newly created

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:CreateFunction20150331` -- new Lambda function created; inspect the `requestParameters.role` field to identify the role being passed — a role with S3 access here is the signal for PassRole abuse targeting bucket data
- `lambda:AddPermission20150331v2` -- resource-based policy added to a Lambda function; high suspicion when the principal being granted rights is the same as the function creator
- `lambda:Invoke` -- Lambda function invoked; correlate with preceding CreateFunction and AddPermission events to identify the full attack chain
- `s3:GetObject` -- object retrieved from S3 bucket; high severity when the caller is a newly created Lambda function's execution role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [lambda-006 on pathfinding.cloud](https://pathfinding.cloud/paths/lambda-006) -- technique details and attack graph for PassRole + Lambda CreateFunction + AddPermission
- [MITRE ATT&CK T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- adversary technique for reading data from cloud storage
- [MITRE ATT&CK T1648 - Serverless Execution](https://attack.mitre.org/techniques/T1648/) -- adversary technique using serverless platforms for execution

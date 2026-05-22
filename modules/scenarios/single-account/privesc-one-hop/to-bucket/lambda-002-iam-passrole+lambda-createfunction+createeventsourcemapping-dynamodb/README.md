# Lambda Function Creation + DynamoDB Event Source to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass scoped S3-access role to Lambda function, link to DynamoDB stream for passive execution without requiring InvokeFunction permission
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** lambda-002
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-002-to-bucket-starting-user` IAM user to the `pl-prod-lambda-002-to-bucket-{account_id}-{suffix}` S3 bucket by creating a Lambda function with a scoped S3-access role, linking it to a DynamoDB stream as a passive trigger, and exfiltrating the bucket's flag through a DynamoDB exfil table — no `lambda:InvokeFunction` permission required.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-lambda-002-to-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-lambda-002-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-lambda-002-to-bucket-target-role` -- pass the target role (which has S3 read access) to a Lambda function
- `lambda:CreateFunction` on `*` -- create a Lambda function with the target role as its execution role
- `lambda:CreateEventSourceMapping` on `*` -- link the Lambda function to a DynamoDB stream to trigger it passively

**Helpful** (`pl-prod-lambda-002-to-bucket-starting-user`):
- `dynamodb:ListStreams` -- discover available DynamoDB streams to target
- `dynamodb:DescribeStream` -- get stream ARN and configuration details
- `dynamodb:DescribeTable` -- get table details including stream ARN
- `lambda:ListFunctions` -- verify Lambda function creation
- `lambda:GetFunction` -- confirm function configuration and role
- `lambda:GetEventSourceMapping` -- check event source mapping status and verify activation
- `iam:ListRoles` -- discover roles available for PassRole
- `dynamodb:PutItem` -- trigger Lambda execution by inserting a record into the trigger table
- `dynamodb:GetItem` -- read the exfiltrated flag value from the exfil table after Lambda execution

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable lambda-002-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-002-to-bucket-starting-user` | Starting principal with PassRole, CreateFunction, and CreateEventSourceMapping permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-002-to-bucket-target-role` | Target role with `s3:GetObject` + `s3:ListBucket` on the flag bucket and `dynamodb:PutItem` on the exfil table |
| `arn:aws:s3:::pl-prod-lambda-002-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing `flag.txt` |
| `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-bucket-trigger-table` | DynamoDB table with streams enabled; stream is used as the Lambda event source |
| `arn:aws:dynamodb:{region}:{account_id}:table/pl-prod-lambda-002-to-bucket-exfil-table` | DynamoDB table where the Lambda writes the exfiltrated flag value |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-lambda-002-to-bucket-starting-user`
3. Confirm the starting user lacks direct S3 access to the flag bucket
4. Write and package a malicious Lambda function that reads `flag.txt` from S3 and writes the content to the exfil DynamoDB table
5. Create the Lambda function, passing the target role as its execution role
6. Look up the trigger table's stream ARN and create an event source mapping
7. Poll the event source mapping until its state reaches `Enabled`
8. Insert a record into the trigger table to fire the Lambda via the stream
9. Poll the exfil table until the Lambda has written the flag value
10. Print the exfiltrated flag

#### Resources Created by Attack Script

- Malicious Lambda function (`pl-lambda-002-to-bucket-escalation-fn`) with the target role attached as its execution role
- Lambda event source mapping linking the function to the DynamoDB trigger table stream
- Exfiltrated flag value written to `pl-prod-lambda-002-to-bucket-exfil-table` under key `{pk: "exfil"}`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable lambda-002-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `lambda-002-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission scoped to a role with `s3:GetObject` and `s3:ListBucket` on a sensitive bucket, enabling data access via Lambda
- IAM user has `lambda:CreateFunction` combined with `iam:PassRole` on an S3-access role — a recognized privilege escalation path to sensitive data
- IAM user has `lambda:CreateEventSourceMapping` allowing passive trigger of attacker-controlled Lambda functions without `lambda:InvokeFunction`
- Role `pl-prod-lambda-002-to-bucket-target-role` with S3 bucket read access is passable by a non-privileged user — data exfiltration path exists
- DynamoDB table `pl-prod-lambda-002-to-bucket-trigger-table` has streams enabled and is accessible as a Lambda event source, expanding the attack surface

#### Prevention Recommendations

- **Restrict PassRole permissions**: Use resource-based conditions to limit which roles can be passed to Lambda functions. Combine a `"StringEquals": {"iam:PassedToService": "lambda.amazonaws.com"}` condition with explicit role ARN restrictions so only intended functions can assume sensitive roles.
- **Implement Service Control Policies (SCPs)**: At the organization level, deny `lambda:CreateFunction` when used together with `iam:PassRole` targeting roles that have read access to sensitive S3 buckets.
- **Restrict CreateEventSourceMapping**: Limit which principals can create event source mappings, especially for DynamoDB streams. Audit regularly for new mappings created by low-privilege users.
- **Enable Lambda function code signing**: Require code signing for Lambda deployments to prevent unauthorized code from being deployed with privileged roles.
- **Apply S3 bucket policies with deny conditions**: Add explicit deny statements on the target bucket for `s3:GetObject` unless the request originates from trusted, known Lambda function ARNs or specific VPC endpoints.
- **Use IAM Access Analyzer**: Regularly scan for privilege escalation and data-access paths involving PassRole combined with Lambda or other compute creation permissions. Access Analyzer external and unused access findings can surface these paths before they are exploited.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `lambda:CreateFunction20150331` -- new Lambda function created; inspect `requestParameters.role` to identify the role being passed — a role with S3 access here is the primary signal for this attack path
- `lambda:CreateEventSourceMapping` -- Lambda function linked to a DynamoDB stream trigger; suspicious when the function was recently created by a low-privilege user
- `dynamodb:PutItem` -- record inserted into the trigger table; may indicate attacker-initiated Lambda execution via stream
- `s3:GetObject` -- object retrieved from the target S3 bucket; high severity when the requesting principal is a Lambda execution role recently attached by a low-privilege user
- `dynamodb:PutItem` -- second occurrence on the exfil table; flag content written by the Lambda execution role; correlate with the trigger table write and `lambda:CreateFunction20150331` events

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Lambda Function Creation + DynamoDB Event Source to Admin](../to-admin/lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb/README.md) -- the to-admin variant of this same technique
- [https://pathfinding.cloud/paths/lambda-002](https://pathfinding.cloud/paths/lambda-002) -- pathfinding.cloud path entry for lambda-002

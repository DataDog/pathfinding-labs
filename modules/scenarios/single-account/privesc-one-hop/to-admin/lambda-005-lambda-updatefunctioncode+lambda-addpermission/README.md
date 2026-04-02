# Privilege Escalation via lambda:UpdateFunctionCode + lambda:AddPermission

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Modifying existing Lambda function code and adding resource-based permissions to execute malicious logic under privileged execution role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** lambda-005
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1648 - Serverless Execution

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-lambda-005-to-admin-starting-user` IAM user to the `pl-prod-lambda-005-to-admin-lambda-exec-role` administrative role by modifying an existing Lambda function's code with a malicious payload, granting yourself invocation rights via a resource-based policy, and executing the function to attach AdministratorAccess to your user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-lambda-005-to-admin-lambda-exec-role`

### Starting Permissions

**Required:**
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-admin-target-lambda` -- replace existing function code with a malicious payload
- `lambda:AddPermission` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-admin-target-lambda` -- add a resource-based policy statement granting self-invocation
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-lambda-005-to-admin-target-lambda` -- trigger execution of the malicious payload under the privileged role

**Helpful:**
- `lambda:GetFunction` -- discover the target Lambda function and its execution role ARN
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
plabs enable enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission
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
| `arn:aws:iam::{account_id}:user/pl-prod-lambda-005-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-lambda-005-to-admin-target-lambda` | Pre-existing Lambda function that runs benign code (victim workload) |
| `arn:aws:iam::{account_id}:role/pl-prod-lambda-005-to-admin-lambda-exec-role` | Lambda execution role with AdministratorAccess policy attached |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources Created by Attack Script

- AdministratorAccess policy attachment on the starting user
- Resource-based policy statement on the target Lambda function granting self-invocation

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo lambda-005-lambda-updatefunctioncode+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup lambda-005-lambda-updatefunctioncode+lambda-addpermission
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission
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

- **Overly Permissive Lambda Update Access**: Users or roles with `lambda:UpdateFunctionCode` on highly privileged Lambda functions
- **Lambda Functions with Administrative Roles**: Lambda functions whose execution roles have administrative or overly broad permissions
- **Resource Policy Modification Access**: Principals with `lambda:AddPermission` on privileged Lambda functions can bypass resource policy protections
- **Privilege Escalation Path**: The combination of Lambda code update permissions, resource policy modification, and privileged execution roles creates an escalation path
- **Lack of Code Signing**: Lambda functions without code signing enforcement allow arbitrary code execution
- **Missing Resource Conditions**: Lambda policies without resource-specific conditions that limit which functions can be modified

#### Prevention Recommendations

- **Implement Code Signing**: Require Lambda functions to use code signing to prevent unauthorized code modifications
- **Apply Least Privilege**: Lambda execution roles should only have permissions required for their specific business function, never AdministratorAccess
- **Restrict Update Permissions**: Limit `lambda:UpdateFunctionCode` to dedicated CI/CD roles with strict condition keys
- **Protect Resource Policies**: Deny `lambda:AddPermission` except for specific trusted principals using SCPs or permission boundaries
- **Use Resource Conditions**: Apply resource-based IAM conditions to restrict which Lambda functions can be modified by which principals
- **Enable CloudTrail Monitoring**: Alert on `UpdateFunctionCode`, `AddPermission`, and `InvokeFunction` API calls, especially for high-privilege functions
- **Implement SCPs**: Use Service Control Policies to prevent attachment of administrative policies to Lambda execution roles
- **Separate Deployment and Execution**: Use separate AWS accounts or strict boundaries between deployment infrastructure and production workloads
- **Enable Lambda Function URLs Protection**: If using function URLs, ensure authentication is required and resource policies are enforced
- **IAM Access Analyzer**: Use AWS IAM Access Analyzer to identify external access and privilege escalation paths involving Lambda functions
- **Version Control Integration**: Implement deployment pipelines that enforce code review and approval before Lambda updates
- **Monitor Resource Policy Changes**: Alert on `AddPermission` API calls and review Lambda resource policy modifications regularly

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Lambda: UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when the target function has an administrative execution role
- `Lambda: AddPermission20150331v2` -- Resource-based policy statement added to a Lambda function; indicates an attacker may be granting themselves invocation rights
- `Lambda: Invoke` -- Lambda function invoked; high severity when preceded by a code update and permission addition on a privileged function
- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; critical when AdministratorAccess or similar broad policies are attached

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

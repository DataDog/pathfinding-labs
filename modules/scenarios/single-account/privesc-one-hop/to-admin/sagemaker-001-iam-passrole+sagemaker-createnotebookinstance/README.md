# Privilege Escalation via iam:PassRole + sagemaker:CreateNotebookInstance

**Category:** Privilege Escalation
**Sub-Category:** new-passrole
**Path Type:** one-hop
**Target:** to-admin
**Environments:** prod
**Pathfinding.cloud ID:** sagemaker-001
**Technique:** Creating SageMaker notebook instance with admin role and accessing Jupyter terminal to execute commands with elevated privileges

## Overview

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to SageMaker and create notebook instances. The attacker can create a SageMaker notebook instance with an administrative execution role, generate a presigned URL to access the Jupyter environment, and use the built-in terminal to execute AWS CLI commands with the elevated privileges of the notebook's execution role.

This technique is particularly effective because SageMaker notebook instances provide a full Jupyter environment with terminal access and pre-installed AWS CLI tools. Unlike some serverless services that require extracting temporary credentials, SageMaker notebooks allow direct interaction through a web-based terminal. The notebook instance automatically inherits the permissions of its execution role, enabling an attacker to execute arbitrary AWS commands with those privileges.

The attack was documented by Spencer Gietzen of Rhino Security Labs in 2019 as part of comprehensive research into AWS privilege escalation methods. It leverages the machine learning platform's legitimate need for elevated permissions, but exploits overly permissive IAM configurations that allow untrusted users to create their own notebook instances with privileged roles. This creates a persistent environment where an attacker can maintain elevated access for as long as the notebook instance remains running.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-sagemaker-001-to-admin-starting-user` (Scenario-specific starting user with PassRole and CreateNotebookInstance permissions)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-sagemaker-001-to-admin-passable-role` (Admin role passed to SageMaker notebook instance)
- `arn:aws:sagemaker:REGION:PROD_ACCOUNT:notebook-instance/pl-prod-sagemaker-001-to-admin-notebook` (Attacker-created notebook instance with admin role)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-sagemaker-001-to-admin-starting-user] -->|iam:PassRole + sagemaker:CreateNotebookInstance| B[SageMaker Notebook Instance]
    B -->|Executes with| C[pl-prod-sagemaker-001-to-admin-passable-role]
    C -->|sagemaker:CreatePresignedNotebookInstanceUrl| D[Access Jupyter Terminal]
    D -->|Execute AWS CLI Commands| E[Administrator Access]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-sagemaker-001-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Create Notebook Instance**: Use `sagemaker:CreateNotebookInstance` with `iam:PassRole` to create a SageMaker notebook instance that uses the admin passable role as its execution role
3. **Wait for Instance**: Poll the notebook instance status until it reaches the "InService" state (typically 3-5 minutes)
4. **Generate Presigned URL**: Use `sagemaker:CreatePresignedNotebookInstanceUrl` to generate a temporary URL for accessing the Jupyter environment
5. **Access Jupyter Terminal**: Open the presigned URL in a browser and navigate to the Jupyter terminal
6. **Execute Commands**: Use the terminal to run AWS CLI commands with the notebook instance's admin execution role credentials
7. **Verification**: Verify administrator access by listing IAM users or performing other admin-level actions

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-sagemaker-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-sagemaker-001-to-admin-passable-role` | Admin role that can be passed to SageMaker notebook instances (trusted by sagemaker.amazonaws.com) |
| Policy attached to starting user | Grants `iam:PassRole` on passable role, `sagemaker:CreateNotebookInstance`, and `sagemaker:CreatePresignedNotebookInstanceUrl` |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-001-iam-passrole+sagemaker-createnotebookinstance
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a SageMaker notebook instance with an admin execution role
4. Wait for the instance to become available (this may take 3-5 minutes)
5. Generate a presigned URL for accessing the notebook
6. Display instructions for accessing the Jupyter terminal and executing commands
7. Verify successful privilege escalation
8. Output standardized test results for automation

**Note**: The notebook instance will incur costs (~$0.05/hour for ml.t3.medium instance type). The cleanup script should be run promptly after testing.

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the SageMaker notebook instance created during the demo:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-001-iam-passrole+sagemaker-createnotebookinstance
./cleanup_attack.sh
```

The cleanup script will:
- Stop the SageMaker notebook instance (if running)
- Delete the notebook instance
- Wait for deletion to complete (typically 1-2 minutes)
- Confirm successful cleanup

This restores the environment to its original state while preserving the deployed infrastructure for future testing.

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0002 - Execution
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials


## Prevention recommendations

- Restrict `iam:PassRole` permissions using strict resource conditions to limit which roles can be passed to SageMaker: `"Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}`
- Implement naming patterns or resource tags to restrict which roles can be used as SageMaker execution roles
- Avoid granting `sagemaker:CreateNotebookInstance` to users who don't require machine learning capabilities
- Use resource-based conditions to restrict notebook instance creation to specific VPCs or subnets: `"Condition": {"StringEquals": {"sagemaker:VpcSubnets": ["subnet-specific-id"]}}`
- Monitor CloudTrail for `CreateNotebookInstance` events where execution roles have administrative or highly privileged permissions
- Implement Service Control Policies (SCPs) that prevent passing roles with `AdministratorAccess` or sensitive permissions to SageMaker
- Enable AWS Config rules to detect SageMaker notebook instances with overly permissive execution roles
- Use IAM Access Analyzer to identify privilege escalation paths involving `iam:PassRole` and SageMaker services
- Consider requiring direct internet access to be disabled for notebook instances: `"Condition": {"StringEquals": {"sagemaker:DirectInternetAccess": "Disabled"}}`
- Require MFA for sensitive operations like creating notebook instances with privileged roles
- Implement VPC restrictions to limit network access from notebook instances to sensitive resources
- Use AWS Organizations SCPs to prevent SageMaker usage in accounts where machine learning is not a business requirement

## Cost considerations

This scenario incurs ongoing AWS costs while the notebook instance is running:
- **Instance Type**: ml.t3.medium (default in demo)
- **Hourly Cost**: ~$0.05/hour (~$36/month if left running)
- **Storage**: 5GB EBS volume (minimal cost, ~$0.50/month)

**Important**: Always run the cleanup script after testing to avoid unnecessary charges. The Terraform-deployed infrastructure (IAM users and roles) has no ongoing costs, but any manually created notebook instances will continue to incur charges until deleted.

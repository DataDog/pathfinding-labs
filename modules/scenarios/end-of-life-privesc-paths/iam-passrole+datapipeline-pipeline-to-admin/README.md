# Privilege Escalation via iam:PassRole + AWS Data Pipeline

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Pathfinding.cloud ID:** datapipeline-001
* **Technique:** Creating a Data Pipeline with an admin role to execute commands with elevated privileges

## Overview

This scenario demonstrates a sophisticated privilege escalation vulnerability where an attacker with `iam:PassRole` and AWS Data Pipeline permissions can gain administrator access. AWS Data Pipeline is a web service designed to reliably process and move data between different AWS compute and storage services. However, when misconfigured, it can be weaponized for privilege escalation.

The attack works by creating a Data Pipeline that launches an EC2 instance with an administrative IAM role. The pipeline definition includes a ShellCommandActivity that executes AWS CLI commands with the elevated permissions of the attached role. In this scenario, the malicious command attaches the AdministratorAccess managed policy to the attacker's starting user, granting full administrative privileges.

This technique is particularly dangerous because Data Pipeline operations are legitimate AWS services that may not trigger immediate security alerts. The privilege escalation occurs through infrastructure-as-code patterns that appear normal in many AWS environments, making it difficult to distinguish from legitimate automation workflows.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-datapipeline-001-to-admin-starting-user` (Scenario-specific starting user)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-datapipeline-001-to-admin-pipeline-role` (Admin role passed to Data Pipeline EC2 instance)
- `arn:aws:ec2:REGION:PROD_ACCOUNT:instance/i-xxxxxxxxx` (EC2 instance launched by Data Pipeline with admin role)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-datapipeline-001-to-admin-starting-user] -->|datapipeline:CreatePipeline| B[Data Pipeline]
    B -->|datapipeline:PutPipelineDefinition| C[Pipeline Definition]
    C -->|iam:PassRole| D[pl-prod-datapipeline-001-to-admin-pipeline-role]
    D -->|datapipeline:ActivatePipeline| E[EC2 Instance with Admin Role]
    E -->|Execute ShellCommandActivity| F[aws iam attach-user-policy]
    F -->|AdministratorAccess| G[Starting User becomes Admin]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#ffcc99,stroke:#333,stroke-width:2px
    style F fill:#ffcc99,stroke:#333,stroke-width:2px
    style G fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-datapipeline-001-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Create Pipeline**: Use `datapipeline:CreatePipeline` to create a new Data Pipeline
3. **Define Pipeline with Malicious Payload**: Use `datapipeline:PutPipelineDefinition` to configure:
   - EC2Resource that will launch an EC2 instance
   - ShellCommandActivity containing: `aws iam attach-user-policy --user-name pl-prod-datapipeline-001-to-admin-starting-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess`
   - Pass the admin role `pl-prod-datapipeline-001-to-admin-pipeline-role` to the EC2 resource using `iam:PassRole`
4. **Activate Pipeline**: Use `datapipeline:ActivatePipeline` to start pipeline execution
5. **Wait for Execution**: The pipeline launches an EC2 instance with the admin role attached
6. **Command Execution**: The ShellCommandActivity executes, attaching AdministratorAccess to the starting user
7. **Verification**: Verify administrator access as the starting user (now with AdministratorAccess)

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-datapipeline-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-datapipeline-001-to-admin-pipeline-role` | Administrative role that can be passed to Data Pipeline EC2 instances |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-datapipeline-001-to-admin-starting-policy` | Policy granting Data Pipeline permissions and iam:PassRole |
| `arn:aws:datapipeline:REGION:PROD_ACCOUNT:pipeline/df-*` | Data Pipeline created during attack (ephemeral) |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+datapipeline-pipeline
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create and activate a Data Pipeline with an admin role
4. Wait for the pipeline to execute the privilege escalation command
5. Verify successful privilege escalation to administrator access
6. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the AdministratorAccess policy attachment and Data Pipeline resources:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-passrole+datapipeline-pipeline
./cleanup_attack.sh
```

This will:
- Detach the AdministratorAccess managed policy from the starting user
- Delete the Data Pipeline created during the attack
- Terminate any EC2 instances launched by the pipeline

## Detection and prevention

### CSPM Detection Guidance

A properly configured Cloud Security Posture Management (CSPM) tool should detect this vulnerability by identifying:

1. **IAM Role with PassRole Permissions**: Identify roles/users with `iam:PassRole` permissions on administrative roles
2. **Data Pipeline Permissions**: Flag principals with both `iam:PassRole` and Data Pipeline creation permissions (`datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, `datapipeline:ActivatePipeline`)
3. **Administrative Role Usage**: Detect when administrative roles are configured as EC2 instance profiles that can be passed to services
4. **Privilege Escalation Path**: Graph-based analysis showing path from low-privilege user to admin access via Data Pipeline
5. **CloudTrail Monitoring**: Alert on suspicious patterns:
   - `CreatePipeline` followed by `PutPipelineDefinition` with ShellCommandActivity
   - `ActivatePipeline` API calls from non-automation principals
   - `AttachUserPolicy` or `PutUserPolicy` calls originating from EC2 instances
   - EC2 instances launched by Data Pipeline with administrative roles

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0003 - Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Technique**: T1578 - Modify Cloud Compute Infrastructure
- **Sub-technique**: Using cloud services to launch compute resources with elevated privileges

## Prevention recommendations

- **Restrict iam:PassRole**: Implement strict resource-based conditions on `iam:PassRole` permissions to prevent passing administrative roles to services:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/LimitedServiceRole",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "datapipeline.amazonaws.com"
      }
    }
  }
  ```

- **Service Control Policies (SCPs)**: Use AWS Organizations SCPs to prevent Data Pipeline creation in accounts where it's not needed:
  ```json
  {
    "Effect": "Deny",
    "Action": [
      "datapipeline:CreatePipeline",
      "datapipeline:PutPipelineDefinition",
      "datapipeline:ActivatePipeline"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/ApprovedAutomationRole"
      }
    }
  }
  ```

- **Least Privilege for Roles**: Avoid granting administrative permissions to roles that can be passed to AWS services. Create service-specific roles with minimal permissions required for the task.

- **CloudTrail Monitoring**: Implement automated alerting for suspicious Data Pipeline activities:
  - CreatePipeline, PutPipelineDefinition, and ActivatePipeline from non-automation principals
  - Data Pipeline definitions containing ShellCommandActivity with IAM-related commands
  - AttachUserPolicy or AttachRolePolicy API calls from EC2 instances

- **IAM Access Analyzer**: Enable IAM Access Analyzer to continuously evaluate IAM policies and identify privilege escalation paths through service integrations.

- **Resource Tagging and Monitoring**: Tag all Data Pipeline resources and monitor for untagged or improperly tagged pipelines that may indicate unauthorized creation.

- **VPC and Network Controls**: Configure Data Pipeline EC2 instances to launch in private subnets without internet access when possible, limiting the attack surface for command execution.

## References

- [AWS Data Pipeline Documentation](https://docs.aws.amazon.com/datapipeline/)
- [Bishop Fox - Privilege Escalation via Data Pipeline](https://bishopfox.com/blog/privilege-escalation-in-aws)
- [Rhino Security Labs - AWS IAM Privilege Escalation Techniques](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/)
- [MITRE ATT&CK - T1098.001](https://attack.mitre.org/techniques/T1098/001/)
- [MITRE ATT&CK - T1578](https://attack.mitre.org/techniques/T1578/)

# Privilege Escalation via iam:PassRole + Data Pipeline with Resource Policy Bypass

* **Category:** Privilege Escalation
* **Sub-Category:** service-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Pathfinding.cloud ID:** datapipeline-001
* **Technique:** Create Data Pipeline with passed role to exfiltrate S3 data, bypassing IAM restrictions via overly permissive bucket resource policy

## Overview

This scenario demonstrates a sophisticated privilege escalation and data exfiltration technique using AWS Data Pipeline combined with an overly permissive S3 bucket resource policy. An attacker with `iam:PassRole` and Data Pipeline permissions can create a pipeline that executes arbitrary shell commands on EC2 instances, allowing them to access and exfiltrate sensitive S3 data.

The critical vulnerability in this scenario is the combination of two security weaknesses: (1) the ability to pass roles to Data Pipeline and execute arbitrary commands, and (2) an overly permissive bucket resource policy that allows writes from any principal. Even though the pipeline role only has `s3:GetObject` permissions (read-only), the write operation succeeds because the destination bucket's resource policy grants `s3:PutObject` to `Principal: "*"`, effectively bypassing IAM restrictions.

This attack pattern is particularly dangerous because it demonstrates how resource policies can override restrictive IAM policies, creating unexpected privilege escalation paths. Security teams often focus on IAM policies while overlooking permissive resource policies, making this a common blind spot in cloud security posture. The scenario highlights the importance of analyzing both IAM and resource-based policies together to identify true access paths.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-datapipeline-001-to-bucket-starting-user` (Scenario-specific starting user)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-datapipeline-001-to-bucket-pipeline-role` (Read-only pipeline role with s3:GetObject permissions)
- `arn:aws:ec2:REGION:PROD_ACCOUNT:instance/i-*` (Ephemeral EC2 instance created by Data Pipeline)
- `arn:aws:s3:::pl-sensitive-data-datapipeline-001-PROD_ACCOUNT-SUFFIX` (Sensitive data bucket)
- `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-PROD_ACCOUNT-SUFFIX` (Exfiltration bucket with permissive resource policy)

### Attack Path Diagram

```mermaid
graph LR
    A[Starting User] -->|datapipeline:CreatePipeline<br/>PutPipelineDefinition<br/>ActivatePipeline<br/>iam:PassRole| B[Data Pipeline]
    B -->|Launches EC2 with| C[Pipeline Role<br/>s3:GetObject only]
    C -->|aws s3 cp| D[Sensitive Bucket]
    C -->|Write via Resource Policy| E[Exfil Bucket<br/>Principal: '*' allows s3:PutObject]
    E -->|s3:GetObject| A

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcccc,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-datapipeline-001-to-bucket-starting-user` (credentials provided via Terraform outputs)
2. **Create Data Pipeline**: Use `datapipeline:CreatePipeline` to create a new pipeline with a unique pipeline ID
3. **Define Pipeline Activity**: Use `datapipeline:PutPipelineDefinition` to define a `ShellCommandActivity` that executes: `aws s3 cp s3://pl-sensitive-data-datapipeline-001-ACCOUNT-SUFFIX/secret-data.txt s3://pl-exfil-bucket-datapipeline-001-ACCOUNT-SUFFIX/exfiltrated.txt`
4. **Pass Read-Only Role**: Pass the `pl-prod-datapipeline-001-to-bucket-pipeline-role` which only has `s3:GetObject` permissions on the sensitive bucket
5. **Activate Pipeline**: Use `datapipeline:ActivatePipeline` to launch the pipeline, which spins up an EC2 instance
6. **Execute Shell Command**: The EC2 instance runs the shell command, reading from the sensitive bucket (allowed by IAM) and writing to the exfil bucket (allowed by resource policy, despite no IAM write permissions)
7. **Resource Policy Bypass**: The write succeeds because the exfil bucket has a resource policy granting `s3:PutObject` to `Principal: "*"`
8. **Retrieve Exfiltrated Data**: Use `s3:GetObject` to read the exfiltrated data from the exfil bucket
9. **Verification**: Confirm successful data exfiltration from the sensitive bucket

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-datapipeline-001-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-datapipeline-001-to-bucket-pipeline-role` | Read-only pipeline role with s3:GetObject on sensitive bucket |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-datapipeline-001-to-bucket-starting-user-policy` | Policy granting Data Pipeline and iam:PassRole permissions |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-datapipeline-001-to-bucket-pipeline-policy` | Policy granting s3:GetObject on sensitive bucket |
| `arn:aws:s3:::pl-sensitive-data-datapipeline-001-PROD_ACCOUNT-SUFFIX` | Sensitive data bucket containing secret data |
| `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-PROD_ACCOUNT-SUFFIX` | Exfiltration bucket with overly permissive resource policy |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-passrole+datapipeline-pipeline
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create the Data Pipeline with shell command activity
4. Activate the pipeline and wait for EC2 instance launch
5. Verify successful data exfiltration from the sensitive bucket
6. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the Data Pipeline, EC2 instances, and exfiltrated data:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-passrole+datapipeline-pipeline
./cleanup_attack.sh
```

The cleanup script will delete the pipeline, terminate any running EC2 instances, and remove the exfiltrated data from the exfil bucket.

## Detection and prevention

### What should CSPM tools detect?

A properly configured Cloud Security Posture Management (CSPM) tool should identify:

1. **Data Pipeline Privilege Escalation Path**:
   - User/role has `iam:PassRole` permission on roles with sensitive permissions
   - User/role has `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` permissions
   - Roles that can be passed to Data Pipeline have access to sensitive S3 buckets
   - Potential for arbitrary command execution via ShellCommandActivity

2. **Overly Permissive S3 Bucket Resource Policy**:
   - S3 bucket resource policy grants permissions to `Principal: "*"` (any AWS principal)
   - S3 bucket allows `s3:PutObject` from all principals without restrictive conditions
   - Resource policy effectively bypasses IAM policy restrictions
   - Public or overly broad write access to buckets

3. **Resource Policy Bypass Vulnerability**:
   - IAM policies restrict write access, but resource policies grant it
   - Potential for privilege escalation through resource policy exploitation
   - Mismatch between IAM and resource-based policy intent

4. **High-Risk Permission Combinations**:
   - Combination of `iam:PassRole` with compute service creation permissions
   - Ability to execute arbitrary code through AWS services
   - Access to sensitive data buckets through compute services

### MITRE ATT&CK Mapping

- **Tactics**:
  - Privilege Escalation (TA0004)
  - Collection (TA0009)
  - Exfiltration (TA0010)
- **Techniques**:
  - T1098.001 - Account Manipulation: Additional Cloud Credentials
  - T1578 - Modify Cloud Compute Infrastructure
  - T1530 - Data from Cloud Storage Object

### References

This scenario is based on privilege escalation techniques documented by:
- [Bishop Fox - AWS IAM Privilege Escalation Techniques](https://bishopfox.com/blog/privilege-escalation-in-aws) - Documented by Rhino Security Labs
- [AWS Data Pipeline Security Best Practices](https://docs.aws.amazon.com/datapipeline/latest/DeveloperGuide/dp-security-best-practices.html)

## Prevention recommendations

1. **Implement Least Privilege for iam:PassRole**:
   - Restrict `iam:PassRole` to specific roles using resource-level conditions: `"Resource": "arn:aws:iam::ACCOUNT:role/specific-role"`
   - Use `iam:PassedToService` condition key to limit which services can receive roles: `"Condition": {"StringEquals": {"iam:PassedToService": "datapipeline.amazonaws.com"}}`
   - Avoid granting broad `iam:PassRole` on `Resource: "*"`

2. **Restrict Data Pipeline Permissions**:
   - Limit `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` to specific users/roles
   - Require MFA for Data Pipeline creation: `"Condition": {"BoolIfExists": {"aws:MultiFactorAuthPresent": "true"}}`
   - Use Service Control Policies (SCPs) to block Data Pipeline in production accounts if not needed

3. **Eliminate Overly Permissive S3 Bucket Resource Policies**:
   - NEVER use `Principal: "*"` in production bucket policies without restrictive conditions
   - If public access is required, use specific conditions like `aws:PrincipalOrgID`, `aws:SourceIp`, or `aws:SourceVpc`
   - Enable S3 Block Public Access at the account and bucket level
   - Use `aws:PrincipalArn` or `aws:PrincipalAccount` conditions to restrict access to known principals

4. **Implement Defense in Depth for Sensitive Buckets**:
   - Require encryption for all data at rest and in transit
   - Enable S3 Object Lock for critical data to prevent deletion/modification
   - Use VPC Endpoints with policies to restrict bucket access to specific VPCs: `"Condition": {"StringEquals": {"aws:SourceVpc": "vpc-xxxxx"}}`
   - Apply bucket policies that explicitly deny non-compliant access patterns

5. **Monitor Data Pipeline and S3 Activity**:
   - Create CloudWatch alerts for `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` events
   - Monitor for unusual S3 access patterns, especially cross-bucket copies
   - Alert on `s3:PutObject` API calls to sensitive buckets from unexpected principals
   - Use AWS GuardDuty to detect anomalous S3 data access and exfiltration patterns
   - Enable CloudTrail logging and S3 access logs for forensic analysis

6. **Regular Security Audits**:
   - Periodically review all S3 bucket policies for overly permissive statements
   - Use IAM Access Analyzer to identify resources shared with external entities or with overly broad access
   - Audit all principals with `iam:PassRole` permissions and validate necessity
   - Review roles that can be passed to compute services for least privilege compliance
   - Test for resource policy bypass vulnerabilities using tools like Pathfinder Labs

7. **Implement SCPs for Organizational Guardrails**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Deny",
         "Action": [
           "datapipeline:CreatePipeline",
           "datapipeline:PutPipelineDefinition"
         ],
         "Resource": "*",
         "Condition": {
           "StringNotEquals": {
             "aws:PrincipalAccount": "APPROVED_ACCOUNT_ID"
           }
         }
       }
     ]
   }
   ```

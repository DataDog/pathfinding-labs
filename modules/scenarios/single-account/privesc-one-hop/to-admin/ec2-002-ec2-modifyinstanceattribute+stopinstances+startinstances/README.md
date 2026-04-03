# One-Hop Privilege Escalation: ec2:ModifyInstanceAttribute + ec2:StopInstances + ec2:StartInstances

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $10/mo
* **Technique:** EC2 userData injection with cloud-init to extract IMDS credentials
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** ec2-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-002-to-admin-starting-user` IAM user to the `pl-prod-ec2-002-to-admin-target-role` administrative role by stopping an EC2 instance, injecting a malicious cloud-init userData payload, and restarting the instance so the payload extracts temporary IAM credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ec2-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ec2-002-to-admin-starting-user`):
- `ec2:ModifyInstanceAttribute` on `arn:aws:ec2:*:*:instance/*` -- inject the malicious userData payload
- `ec2:StopInstances` on `arn:aws:ec2:*:*:instance/*` -- stop the instance so userData can be modified
- `ec2:StartInstances` on `arn:aws:ec2:*:*:instance/*` -- boot the instance to trigger payload execution

**Helpful** (`pl-prod-ec2-002-to-admin-starting-user`):
- `ec2:DescribeInstances` -- discover target EC2 instances and verify instance state
- `ec2:DescribeInstanceAttribute` -- view current userData and instance configuration
- `sts:GetCallerIdentity` -- verify identity during attack execution

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances
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
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-002-to-admin-starting-user` | Scenario-specific starting user with EC2 modification permissions and access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-002-to-admin-target-role` | Target admin role attached to the EC2 instance |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ec2-002-to-admin-target-profile` | Instance profile wrapping the admin role |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with admin role that becomes the attack vector |
| `arn:aws:ec2:{region}:{account_id}:vpc/vpc-xxxxxxxxx` | VPC for the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:subnet/subnet-xxxxxxxxx` | Subnet for the EC2 instance |
| `arn:aws:ec2:{region}:{account_id}:security-group/sg-xxxxxxxxx` | Security group for the EC2 instance |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate stopping the instance, modifying userData, and starting it
4. Show the malicious script execution and credential extraction
5. Verify successful privilege escalation using the extracted credentials
6. Output standardized test results for automation

#### Resources Created by Attack Script

- Malicious cloud-init userData injected into the target EC2 instance

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-002-ec2-modifyinstanceattribute+stopinstances+startinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the modified userData and restore the instance to its original state.

The cleanup script will:
- Remove the malicious userData from the EC2 instance
- Stop and restart the instance to clear any running malicious processes
- Verify the instance has been restored to a clean state

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-002-ec2-modifyinstanceattribute+stopinstances+startinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances
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

- Principals with `ec2:ModifyInstanceAttribute` on instances with privileged roles attached
- Privilege escalation path: low-privilege principal → EC2 modification permissions → admin role credentials via IMDS
- High-risk permission combination: `ec2:StopInstances` + `ec2:ModifyInstanceAttribute` + `ec2:StartInstances` held by the same principal
- EC2 instances with administrative IAM roles that are modifiable by non-admin principals
- Instances with administrative roles that have IMDSv1 enabled (allowing credential extraction without session tokens)

#### Prevention Recommendations

1. **Restrict ModifyInstanceAttribute Permission**: Use resource-based conditions to limit which instances can have their attributes modified:
   ```json
   {
     "Effect": "Allow",
     "Action": "ec2:ModifyInstanceAttribute",
     "Resource": "arn:aws:ec2:*:*:instance/*",
     "Condition": {
       "StringEquals": {
         "ec2:ResourceTag/AllowUserDataModification": "true"
       }
     }
   }
   ```

2. **Implement SCPs to Prevent High-Risk Modifications**: Create Service Control Policies that prevent userData modification on instances with privileged roles:
   ```json
   {
     "Effect": "Deny",
     "Action": "ec2:ModifyInstanceAttribute",
     "Resource": "arn:aws:ec2:*:*:instance/*",
     "Condition": {
       "StringEquals": {
         "ec2:Attribute": "userData"
       }
     }
   }
   ```

3. **Require IMDSv2**: Enforce Instance Metadata Service v2, which requires session tokens and mitigates credential extraction:
   ```bash
   aws ec2 modify-instance-metadata-options \
     --instance-id i-xxxxxxxxx \
     --http-tokens required \
     --http-put-response-hop-limit 1
   ```

4. **Separate EC2 Management from Application Permissions**: Use separate roles for EC2 infrastructure management versus application workloads -- never grant `ec2:ModifyInstanceAttribute` to application-level roles; use dedicated admin roles for EC2 modifications

5. **Implement Network Controls**: Use VPC endpoints and security groups to restrict outbound traffic from sensitive instances, preventing credential exfiltration

6. **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving EC2 permissions and instance roles

7. **Apply Least Privilege for Instance Roles**: Minimize permissions granted to EC2 instance roles, especially for long-running instances

8. **Enable GuardDuty**: AWS GuardDuty can detect anomalous IMDS credential usage and EC2 instance compromise indicators

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `EC2: StopInstances` -- instance stopped; suspicious when followed immediately by ModifyInstanceAttribute and StartInstances on the same instance
- `EC2: ModifyInstanceAttribute` -- instance attribute modified; critical when `attribute=userData` on an instance with a privileged role attached
- `EC2: StartInstances` -- instance started; high severity when preceded by a ModifyInstanceAttribute (userData) event
- `STS: AssumeRole` -- role assumed from EC2 instance metadata; look for the target role ARN being assumed by the EC2 instance principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- **Bishop Fox AWS Privilege Escalation Research**: This technique was documented as part of Bishop Fox's comprehensive research into AWS privilege escalation methods
- **Cloud-init Documentation**: Understanding multipart MIME userData and boot-time script execution
- **AWS IMDS Security**: Best practices for securing Instance Metadata Service access
- **Pathfinding.cloud**: This scenario is cataloged as path ID **ec2-002**


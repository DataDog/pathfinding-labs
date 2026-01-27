# Self-Escalation Privilege Escalation: iam:CreatePolicyVersion

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Environments:** prod
* **Pathfinding.cloud ID:** iam-001
* **Technique:** Self-modification via iam:CreatePolicyVersion

## Overview

This scenario demonstrates a privilege escalation vulnerability where a role can modify its own permissions by creating new versions of policies attached to itself. The attacker starts with minimal permissions but can grant themselves administrator access by creating a new policy version with elevated permissions.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-001-to-admin-starting-user`
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-001-to-admin-starting-role`

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-iam-001-to-admin-starting-user] -->|sts:AssumeRole| B[pl-prod-iam-001-to-admin-starting-role]
    B -->|iam:CreatePolicyVersion| C[pl-prod-iam-001-to-admin-policy v2 with admin]
    C -->|Administrator Access| D[Effective Administrator]
```

### Attack Steps

1. **Initial Access**: `pl-prod-iam-001-to-admin-starting-user` assumes the role `pl-prod-iam-001-to-admin-starting-role` to begin the scenario
2. **Create New Policy Version**: `pl-prod-iam-001-to-admin-starting-role` uses `iam:CreatePolicyVersion` to create a new version of its attached policy with administrator permissions
3. **Verification**: Verify administrator access with the modified policy

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-001-to-admin-starting-user` | Scenario-specific starting user with AssumeRole permission |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-001-to-admin-starting-role` | Starting role with policy versioning capability |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-iam-001-to-admin-policy` | Allows `iam:CreatePolicyVersion` and `iam:ListPolicyVersions` on itself |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-001-iam-createpolicyversion
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the policy versions created during the demo:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-001-iam-createpolicyversion
./cleanup_attack.sh
```

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Sub-technique**: Abuse of IAM Permissions


## Prevention recommendations

- Avoid granting `iam:CreatePolicyVersion` permissions on policies attached to the same role
- If required, use resource-based conditions to restrict which policies can be modified
- Implement SCPs to prevent policy version manipulation for privilege escalation
- Monitor CloudTrail for `CreatePolicyVersion` API calls, especially when roles modify their own policies
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement alerting on policy version changes for critical roles
- Limit the number of policy versions that can exist (AWS allows up to 5)

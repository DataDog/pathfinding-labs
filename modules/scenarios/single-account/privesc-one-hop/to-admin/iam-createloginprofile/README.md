# One-Hop Privilege Escalation: iam:CreateLoginProfile

**Scenario Type:** One-Hop
**Target:** Admin Access
**Technique:** Console credential creation for admin user via iam:CreateLoginProfile

## Overview

This scenario demonstrates a privilege escalation vulnerability where a role has permission to create login profiles for an administrator user. The attacker can assume a role with `iam:CreateLoginProfile` permission on an admin user, create a new console password for that user, and then use those credentials to gain administrator access through the AWS Management Console.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-pathfinder-starting-user-prod`
- `arn:aws:iam::PROD_ACCOUNT:role/pl-clp-clifford`
- `arn:aws:iam::PROD_ACCOUNT:user/pl-clp-admin`

### Attack Path Diagram

```mermaid
graph LR
    A[pl-clp-clifford] -->|iam:CreateLoginProfile| B[pl-clp-admin]
    B -->|Administrator Access| C[Effective Administrator]
```

### Attack Steps

1. **Scaffolding aka Initial Access**: `pl-pathfinder-starting-user-prod` assumes the role `pl-clp-clifford` to begin the scenario
2. **Create Login Profile**: `pl-clp-clifford` uses `iam:CreateLoginProfile` to create a console password for the admin user `pl-clp-admin`
3. **Console Login**: Use the AWS Management Console with the newly created password to login as `pl-clp-admin`
4. **Verification**: Verify administrator access through both console and API

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-clp-clifford` | Starting principal |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-one-hop-createloginprofile-policy` | Allows `iam:CreateLoginProfile` on `pl-clp-admin` only |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-clp-admin` | Destination principal |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createloginprofile
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a console password with a unique random suffix
4. Display console login URL and credentials
5. Verify successful privilege escalation via API access
6. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the login profile created during the demo:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createloginprofile
./cleanup_attack.sh
```

## Detection and prevention

### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation, Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Sub-technique**: Creating console login credentials for privileged accounts

## Prevention recommendations

- Avoid granting `iam:CreateLoginProfile` permissions on privileged users
- Use resource-based conditions to restrict which users can have login profiles created
- Implement SCPs to prevent login profile creation on admin users
- Monitor CloudTrail for `CreateLoginProfile` API calls on privileged accounts
- Enable MFA requirements immediately upon login profile creation
- Use IAM Access Analyzer to identify privilege escalation paths
- Prefer role-based access over user-based access for administrative functions
- Regularly audit IAM users for unexpected login profiles
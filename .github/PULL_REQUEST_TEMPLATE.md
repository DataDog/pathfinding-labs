## What does this PR do?

<!-- Brief description of the change -->

## Motivation

<!-- Why is this change needed? Link to an issue if applicable -->

## Testing

- [ ] Deployed to an isolated AWS sandbox account
- [ ] `demo_attack.sh` runs successfully
- [ ] `cleanup_attack.sh` removes all demo artifacts
- [ ] Terraform plan/apply/destroy cycle completes cleanly

## Checklist

- [ ] Scenario follows naming conventions (`pl-` prefix, correct directory path)
- [ ] `README.md` includes attack path diagram and CSPM detection guidance
- [ ] Boolean variable and module instantiation added to root `variables.tf` / `main.tf` / `outputs.tf`
- [ ] No real AWS credentials or sensitive data committed

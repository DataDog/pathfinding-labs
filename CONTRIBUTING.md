# Contributing

First off, thanks for taking the time to contribute!

## How to Contribute

### Reporting Bugs

Open a [GitHub Issue](https://github.com/DataDog/pathfinding-labs/issues) with:
- A clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- Your environment (OS, AWS region, Terraform version)

### Suggesting New Scenarios

Open an issue with the label `new-scenario` describing:
- The AWS service and privilege escalation technique
- The attack path (e.g., `Principal A → action → Principal B → target`)
- Whether it corresponds to an existing [pathfinding.cloud](https://pathfinding.cloud) path ID

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b my-new-scenario`)
3. Make your changes following the conventions in [CLAUDE.md](CLAUDE.md)
4. Test your scenario by deploying it to an isolated AWS sandbox account
5. Open a pull request against `main`

### Scenario Conventions

- All resources use the `pl-` prefix
- Each scenario lives under `modules/scenarios/<category>/<scenario-name>/`
- Required files: `main.tf`, `variables.tf`, `outputs.tf`, `README.md`, `demo_attack.sh`, `cleanup_attack.sh`
- See [CLAUDE.md](CLAUDE.md) for the full guide

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).

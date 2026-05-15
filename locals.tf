locals {
  # Merge default flags with plabs-configured flags. scenario_flags (written by
  # plabs from flags.default.yaml or a vendor override file) takes precedence,
  # so CTF operators can customize values without touching Terraform source.
  # Raw `terraform apply` with no plabs config still produces real flag values.
  effective_flags = merge(var.scenario_flag_defaults, var.scenario_flags)
}

variable "account_id" {
  description = "The AWS account ID where resources will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, ops)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored in SSM Parameter Store"
  type        = string
  default     = "FLAG{pr0mpt_1nj3ct10n_l34ds_t0_aws_cr3d3nt14l_th3ft}"
}

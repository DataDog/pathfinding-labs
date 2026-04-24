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
  default     = "FLAG{ch41ned_pr0mpt_1nj3ct10n_l4mbd4_p1v0t_t0_4dm1n}"
}

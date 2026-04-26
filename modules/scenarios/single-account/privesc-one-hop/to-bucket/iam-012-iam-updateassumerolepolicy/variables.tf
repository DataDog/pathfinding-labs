variable "account_id" {
  type = string
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "resource_suffix" {
  type = string
}

variable "flag_value" {
  description = "CTF flag value stored as an S3 object in the target bucket. Set via plabs flags (loaded from flags.default.yaml or a vendor override file). Defaults to flag{MISSING} so the module is deployable in isolation."
  type        = string
  default     = "flag{MISSING}"
}


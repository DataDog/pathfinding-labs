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
  description = "CTF flag value placed in the target S3 bucket as flag.txt"
  type        = string
  default     = "flag{MISSING}"
}


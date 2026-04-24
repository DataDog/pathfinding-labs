variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "attacker_account_id" {
  description = "Attacker account ID (for attacker-controlled exfil bucket naming)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value stored as an S3 object in the target bucket"
  type        = string
  default     = "flag{MISSING}"
}

variable "project_id" {
  description = "GCP project ID (analog of AWS account_id)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, ops)"
  type        = string
  default     = "prod"
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources (e.g. GCS bucket names)"
  type        = string
}

variable "flag_value" {
  description = "CTF flag value injected at deploy time"
  type        = string
  default     = "flag{MISSING}"
}

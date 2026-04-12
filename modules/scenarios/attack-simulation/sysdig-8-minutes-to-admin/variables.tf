variable "account_id" {
  description = "AWS Account ID for the prod environment"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources like S3 buckets"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

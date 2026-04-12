variable "operations_account_id" {
  description = "AWS Account ID for the operations account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID for the prod account"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally unique resources (S3 bucket names)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository trusted via OIDC to assume the ops deployer role (format: org/repo)"
  type        = string
}

variable "dev_account_id" {
  description = "The AWS account ID for the dev environment"
  type        = string
}

variable "prod_account_id" {
  description = "The AWS account ID for the prod environment"
  type        = string
}

variable "operations_account_id" {
  description = "The AWS account ID for the operations environment"
  type        = string
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev, operations)"
  type        = string
  default     = "prod"
}

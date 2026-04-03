variable "prod_account_aws_profile" {
  description = "AWS profile for the prod account"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label applied to resource tags"
  type        = string
  default     = "prod"
}

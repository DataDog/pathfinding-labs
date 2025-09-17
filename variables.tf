variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "dev_account_aws_profile" {
  description = "AWS profile for dev environment"
  default     = "pl-pathfinder-starting-user-dev"
}

variable "operations_account_aws_profile" {
  description = "AWS profile for operations account"
  default     = "pl-pathfinder-starting-user-operations"  
}

variable "prod_account_aws_profile" {
  description = "AWS profile for prod account"
  default     = "pl-pathfinder-starting-user-prod"
}

variable "prod_account_id" {
  description = "The account id of the prod account"
  type        = string
  default     = ""
}

variable "operations_account_id" {
  description = "The account id of the operations account"
  type        = string
  default     = ""
}

variable "dev_account_id" {
  description = "The account id of the dev account"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "The github repo for the OIDC-GitHub challenge"
  type        = string
  default     = null
}
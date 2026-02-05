variable "aws_local_profile" {
  description = "What local profile should terraform use to interact with your AWS account(s)"
  type        = string
  default     = "default"
}

variable "aws_local_creds_file" {
  description = "Location of your local credentials file"
  type        = string
  default     = "~/.aws/credentials"
}

variable "aws_assume_role_arn" {
  description = "This is the arn of an already existing principal that can assume into any roles that are created"
  type        = string
  default     = ""
}

variable "account_id" {
  description = "This is the ID of the caller account"
  type        = string
  default     = ""
}


variable "shared_high_priv_servicerole" {
  description = "This is the arn of high priv service role that is attached to lambda's ec2's, etc. to facilitate privesc"
  type        = string
  default     = ""
}

variable "AWS_REGION" {
  type    = string
  default = "us-west-2"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet1_id" {
  type    = string
  default = ""
}

variable "subnet2_id" {
  type    = string
  default = ""
}

variable "subnet3_id" {
  type    = string
  default = ""
}


variable "user_ip" {
  description = "The current user's IP address"
  type        = string
  default     = ""
}

variable "ctf_starting_user_arn" {
  description = "The arn of the user that is created at the start of the CTF"
  type        = string
  default     = ""
}

variable "ctf_starting_user_name" {
  description = "The name of the user that is created at the start of the CTF"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "dev_account_aws_profile" {
  description = "AWS profile for dev environment"
  default     = "pl-dev.AWSAdministratorAccess"
}

variable "operations_account_aws_profile" {
  description = "AWS profile for operations account"
  default     = "pl-ops.AWSAdministratorAccess"
}

variable "prod_account_aws_profile" {
  description = "AWS profile for prod account"
  default     = "pl-prod.AWSAdministratorAccess"
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

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}
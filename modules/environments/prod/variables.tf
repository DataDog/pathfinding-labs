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


# Resources
resource "random_password" "database-secret" {
  length           = 31
  special          = true
  min_special      = 5
  override_special = "!#$%^&*()-_=+[]{}<>:?"
  keepers = {
    pass_version = 1
  }
}

resource "random_password" "app-secret" {
  length           = 31
  special          = true
  min_special      = 5
  override_special = "!#$%^&*()-_=+[]{}<>:?"
  keepers = {
    pass_version = 1
  }
}

resource "random_string" "resource-suffix" {
  length  = 5
  upper   = false
  special = false
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

variable "dev_account_id" {
  description = "The account id of the dev account"
  type        = string
  default     = ""
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

variable "prod_account_aws_profile" {
  description = "AWS profile for prod account"
  default     = ""
}

variable "resource_suffix" {
  description = "Random suffix for globally namespaced resources to prevent conflicts"
  type        = string
}

##############################################################################
# BUDGET ALERT CONFIGURATION
##############################################################################

variable "enable_budget_alerts" {
  description = "Enable AWS Budget alerts for this environment"
  type        = bool
  default     = false
}

variable "budget_alert_email" {
  description = "Email address to receive budget alerts"
  type        = string
  default     = ""
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 50
}

variable "github_repo" {
  description = "The github repo for the OIDC-GitHub challenge"
  type        = string
  default     = null
}

##############################################################################
# SERVICE-LINKED ROLE CREATION FLAGS
# Set to false if the role already exists in the account.
# The plabs CLI auto-detects these; manual users can override in tfvars.
##############################################################################

variable "create_autoscaling_slr" {
  description = "Create the Auto Scaling service-linked role (set false if it already exists)"
  type        = bool
  default     = true
}

variable "create_spot_slr" {
  description = "Create the EC2 Spot service-linked role (set false if it already exists)"
  type        = bool
  default     = true
}

variable "create_apprunner_slr" {
  description = "Create the App Runner service-linked role (set false if it already exists)"
  type        = bool
  default     = true
}

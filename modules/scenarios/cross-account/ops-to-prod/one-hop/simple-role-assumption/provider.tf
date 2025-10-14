terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      configuration_aliases = [aws.prod, aws.operations]
    }
  }
}

# # provider "aws" {
# #   alias   = "dev2"
# #   profile = var.dev_account_aws_profile
# #   region  = "us-west-2"
# # }

# provider "aws" {
#   alias   = "operations"
#   profile = var.operations_account_aws_profile
#   region  = "us-west-2"
# }

# provider "aws" {
#   alias   = "prod"
#   profile = var.prod_account_aws_profile
#   region  = "us-west-2"
# }
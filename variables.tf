##############################################################################
# ACCOUNT CONFIGURATION
##############################################################################

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

##############################################################################
# PROD ONE-HOP TO-ADMIN SCENARIOS
##############################################################################

variable "enable_prod_one_hop_to_admin_iam_putrolepolicy" {
  description = "Enable: prod → one-hop → to-admin → iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_iam_attachrolepolicy" {
  description = "Enable: prod → one-hop → to-admin → iam-attachrolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_iam_createpolicyversion" {
  description = "Enable: prod → one-hop → to-admin → iam-createpolicyversion"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_iam_createaccesskey" {
  description = "Enable: prod → one-hop → to-admin → iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_sts_assumerole" {
  description = "Enable: prod → one-hop → to-admin → sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_admin_iam_updateassumerolepolicy" {
  description = "Enable: prod → one-hop → to-admin → iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

##############################################################################
# PROD ONE-HOP TO-BUCKET SCENARIOS
##############################################################################

variable "enable_prod_one_hop_to_bucket_iam_putrolepolicy" {
  description = "Enable: prod → one-hop → to-bucket → iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_bucket_iam_attachrolepolicy" {
  description = "Enable: prod → one-hop → to-bucket → iam-attachrolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_bucket_iam_createaccesskey" {
  description = "Enable: prod → one-hop → to-bucket → iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_bucket_iam_updateassumerolepolicy" {
  description = "Enable: prod → one-hop → to-bucket → iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_prod_one_hop_to_bucket_sts_assumerole" {
  description = "Enable: prod → one-hop → to-bucket → iam-assumerole"
  type        = bool
  default     = false
}

##############################################################################
# PROD MULTI-HOP TO-ADMIN SCENARIOS
##############################################################################

variable "enable_prod_multi_hop_to_admin_putrolepolicy_on_other" {
  description = "Enable: prod → multi-hop → to-admin → putrolepolicy-on-other"
  type        = bool
  default     = false
}

variable "enable_prod_multi_hop_to_admin_multiple_paths_combined" {
  description = "Enable: prod → multi-hop → to-admin → multiple-paths-combined"
  type        = bool
  default     = false
}

##############################################################################
# PROD MULTI-HOP TO-BUCKET SCENARIOS
##############################################################################

variable "enable_prod_multi_hop_to_bucket_role_chain_to_s3" {
  description = "Enable: prod → multi-hop → to-bucket → role-chain-to-s3"
  type        = bool
  default     = false
}

variable "enable_prod_multi_hop_to_bucket_resource_policy_bypass" {
  description = "Enable: prod → multi-hop → to-bucket → resource-policy-bypass"
  type        = bool
  default     = false
}

variable "enable_prod_multi_hop_to_bucket_exclusive_resource_policy" {
  description = "Enable: prod → multi-hop → to-bucket → exclusive-resource-policy"
  type        = bool
  default     = false
}

##############################################################################
# PROD TOXIC-COMBO SCENARIOS
##############################################################################

variable "enable_prod_toxic_combo_public_lambda_with_admin" {
  description = "Enable: prod → toxic-combo → public-lambda-with-admin"
  type        = bool
  default     = false
}

##############################################################################
# CROSS-ACCOUNT DEV-TO-PROD SCENARIOS
##############################################################################

variable "enable_cross_account_dev_to_prod_one_hop_simple_role_assumption" {
  description = "Enable: cross-account → dev-to-prod → one-hop → simple-role-assumption"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → passrole-lambda-admin"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_multi_hop_both_sides" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → multi-hop-both-sides"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → lambda-invoke-update"
  type        = bool
  default     = false
}

##############################################################################
# CROSS-ACCOUNT OPS-TO-PROD SCENARIOS
##############################################################################

variable "enable_cross_account_ops_to_prod_one_hop_simple_role_assumption" {
  description = "Enable: cross-account → ops-to-prod → one-hop → simple-role-assumption"
  type        = bool
  default     = false
}

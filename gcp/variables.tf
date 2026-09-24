variable "gcp_region" {
  description = "GCP region to deploy resources into"
  type        = string
  default     = "us-central1"
}

variable "prod_project_id" {
  description = "GCP project ID for the prod environment"
  type        = string
}

variable "dev_project_id" {
  description = "GCP project ID for the dev environment (optional — falls back to prod project)"
  type        = string
  default     = ""
}

variable "operations_project_id" {
  description = "GCP project ID for the operations environment (optional — falls back to prod project)"
  type        = string
  default     = ""
}

##############################################################################
# ENVIRONMENT ENABLEMENT FLAGS
##############################################################################

variable "enable_gcp_prod_environment" {
  description = "Enable the prod environment (admin cleanup + readonly service accounts)"
  type        = bool
  default     = true
}

variable "enable_gcp_dev_environment" {
  description = "Enable the dev environment (for cross-account scenarios)"
  type        = bool
  default     = false
}

variable "enable_gcp_ops_environment" {
  description = "Enable the ops environment (for cross-account scenarios)"
  type        = bool
  default     = false
}

variable "scenario_flags" {
  description = "Map of scenario ID to CTF flag value, used by scenarios that support flag capture"
  type        = map(string)
  default     = {}
}

##############################################################################
# GCP SCENARIO ENABLEMENT FLAGS
##############################################################################
# Added here as GCP contributions land, following the same
# enable_single_account_privesc_{category}_to_{target}_{path_id} convention
# used by the AWS root's variables.tf.

# SINGLE-ACCOUNT PRIVESC ONE-HOP TO-ADMIN

variable "enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate" {
  description = "Enable: gcp single-account → privesc-one-hop → to-admin → gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate"
  type        = bool
  default     = false
}

variable "enable_gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken" {
  description = "Enable: gcp single-account → privesc-one-hop → to-admin → gcp-iam-001-iam-serviceaccountsgetaccesstoken"
  type        = bool
  default     = false
}

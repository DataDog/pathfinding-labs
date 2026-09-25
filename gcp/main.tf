terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Path is supplied at init time via `-backend-config=path=...` (plabs always
  # passes this cloud's canonical state path under ~/.plabs/state/), kept
  # entirely separate from the AWS root's state so GCP-only users never need
  # AWS credentials configured, and vice versa.
  backend "local" {}
}

locals {
  # Fall back to prod project when dev/ops projects are not configured,
  # allowing single-project mode to work without errors.
  effective_dev_project = coalesce(var.dev_project_id, var.prod_project_id)
  effective_ops_project = coalesce(var.operations_project_id, var.prod_project_id)
}

provider "google" {
  alias   = "prod"
  project = var.prod_project_id
  region  = var.gcp_region
}

provider "google" {
  alias   = "dev"
  project = local.effective_dev_project
  region  = var.gcp_region
}

provider "google" {
  alias   = "operations"
  project = local.effective_ops_project
  region  = var.gcp_region
}

# Random suffix for globally namespaced resources to prevent conflicts
resource "random_string" "resource_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

##############################################################################
# ENVIRONMENT MODULES
##############################################################################

# Prod environment (enabled by default)
module "gcp_prod_environment" {
  count  = var.enable_gcp_prod_environment ? 1 : 0
  source = "../modules/environments/gcp"
  providers = {
    google = google.prod
  }
  environment_name = "prod"
  project_id       = var.prod_project_id
  resource_suffix  = random_string.resource_suffix.result
}

# Dev environment is optional (for cross-account scenarios)
module "gcp_dev_environment" {
  count  = var.enable_gcp_dev_environment ? 1 : 0
  source = "../modules/environments/gcp"
  providers = {
    google = google.dev
  }
  environment_name = "dev"
  project_id       = local.effective_dev_project
  resource_suffix  = random_string.resource_suffix.result
}

# Ops environment is optional (for cross-account scenarios)
module "gcp_ops_environment" {
  count  = var.enable_gcp_ops_environment ? 1 : 0
  source = "../modules/environments/gcp"
  providers = {
    google = google.operations
  }
  environment_name = "ops"
  project_id       = local.effective_ops_project
  resource_suffix  = random_string.resource_suffix.result
}

##############################################################################
# GCP SCENARIO MODULES
##############################################################################
# Scenario modules are added here as GCP contributions land — sourced from
# ../modules/scenarios/gcp/... and gated by their own enable_* boolean,
# following the same convention as the AWS root's scenario modules.

module "gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate" {
  count  = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate ? 1 : 0
  source = "../modules/scenarios/gcp/single-account/privesc-one-hop/to-admin/gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate"

  providers = {
    google.prod = google.prod
  }

  project_id      = var.prod_project_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
  region          = var.gcp_region
  flag_value      = lookup(var.scenario_flags, "gcp-cloudfunctions-001-to-admin", "flag{MISSING}")
}

module "gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate" {
  count  = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate ? 1 : 0
  source = "../modules/scenarios/gcp/single-account/privesc-one-hop/to-admin/gcp-cloudfunctions-002-cloudfunctions-functionsupdate"

  providers = {
    google.prod = google.prod
  }

  project_id      = var.prod_project_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
  region          = var.gcp_region
  flag_value      = lookup(var.scenario_flags, "gcp-cloudfunctions-002-to-admin", "flag{MISSING}")
}

module "gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken" {
  count  = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken ? 1 : 0
  source = "../modules/scenarios/gcp/single-account/privesc-one-hop/to-admin/gcp-iam-001-iam-serviceaccountsgetaccesstoken"

  providers = {
    google.prod = google.prod
  }

  project_id      = var.prod_project_id
  environment     = "prod"
  resource_suffix = random_string.resource_suffix.result
  flag_value      = lookup(var.scenario_flags, "gcp-iam-001-to-admin", "flag{MISSING}")
}

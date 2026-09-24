##############################################################################
# REQUIRED APIS
##############################################################################
# Enable APIs that every GCP scenario environment needs.
# disable_on_destroy = false: we don't want to break the project when
# the environment module is destroyed, since other workloads may use these.

resource "google_project_service" "iam" {
  project                    = var.project_id
  service                    = "iam.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "cloudresourcemanager" {
  project                    = var.project_id
  service                    = "cloudresourcemanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

##############################################################################
# DEPLOYER IDENTITY
##############################################################################
# Auto-detect who ran terraform apply. We grant this identity
# serviceAccountTokenCreator on the environment SAs so demo and cleanup
# scripts can impersonate them without needing static SA keys — which are
# blocked by the constraints/iam.managed.disableServiceAccountKeyCreation
# org policy that many GCP orgs enforce.

data "google_client_openid_userinfo" "deployer" {}

locals {
  deployer_email = data.google_client_openid_userinfo.deployer.email
  # google_service_account_iam_member expects "user:<email>" for human
  # identities and "serviceAccount:<email>" for SAs. Distinguish by the
  # well-known suffix all SA emails share.
  deployer_member = endswith(local.deployer_email, ".iam.gserviceaccount.com") ? "serviceAccount:${local.deployer_email}" : "user:${local.deployer_email}"
}

##############################################################################
# GCP ADMIN CLEANUP SERVICE ACCOUNT
##############################################################################
# Used by scenario cleanup scripts to revert attack artifacts after a demo,
# mirroring the AWS admin_user_for_cleanup pattern (modules/environments/prod).
# Cleanup scripts impersonate this SA using the deployer's ADC — no static key.

resource "google_service_account" "admin_cleanup" {
  project      = var.project_id
  account_id   = "pl-admin-cleanup-${var.environment_name}-${var.resource_suffix}"
  display_name = "Pathfinding Labs admin cleanup (${var.environment_name})"
}

resource "google_project_iam_member" "admin_cleanup_owner" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.admin_cleanup.email}"
}

# Grant the deployer serviceAccountTokenCreator so cleanup scripts can
# impersonate this SA with --impersonate-service-account.
resource "google_service_account_iam_member" "admin_cleanup_deployer_impersonation" {
  service_account_id = google_service_account.admin_cleanup.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.deployer_member
}

##############################################################################
# GCP READONLY SERVICE ACCOUNT
##############################################################################
# Used by demo scripts to observe/verify state without attacker-level
# credentials, mirroring the AWS readonly_user pattern.
# Demo scripts impersonate this SA using the deployer's ADC — no static key.

resource "google_service_account" "readonly" {
  project      = var.project_id
  account_id   = "pl-readonly-${var.environment_name}-${var.resource_suffix}"
  display_name = "Pathfinding Labs readonly (${var.environment_name})"
}

resource "google_project_iam_member" "readonly_viewer" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.readonly.email}"
}

# Grant the deployer serviceAccountTokenCreator so demo scripts can
# impersonate this SA with --impersonate-service-account.
resource "google_service_account_iam_member" "readonly_deployer_impersonation" {
  service_account_id = google_service_account.readonly.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.deployer_member
}

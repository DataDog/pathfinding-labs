terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
  }
}

locals {
  path_id = "gcp-iam-003"
  # Determine the IAM member string for whoever ran terraform apply.
  # google_client_openid_userinfo returns the ADC identity email; the member
  # prefix differs for human users vs service accounts.
  deployer_member = endswith(data.google_client_openid_userinfo.deployer.email, ".iam.gserviceaccount.com") ? "serviceAccount:${data.google_client_openid_userinfo.deployer.email}" : "user:${data.google_client_openid_userinfo.deployer.email}"
}

# Auto-detect the deployer's identity so we can grant them impersonation
# rights on the starting SA — no user-supplied email needed, no static key.
data "google_client_openid_userinfo" "deployer" {
  provider = google.prod
}

# -----------------------------------------------------------------------------
# Starting Service Account (attacker's initial identity)
# -----------------------------------------------------------------------------

resource "google_service_account" "starting_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.path_id}-start"
  display_name = "Pathfinding Labs - ${var.environment} - iam-rolesupdate - Starting SA"
}

# Grant the deployer serviceAccountTokenCreator on starting_sa so demo scripts
# can impersonate it with --impersonate-service-account. No static key is
# created — this works even when org policy blocks SA key creation.
resource "google_service_account_iam_member" "starting_sa_deployer_impersonation" {
  provider           = google.prod
  service_account_id = google_service_account.starting_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.deployer_member
}

# -----------------------------------------------------------------------------
# The vulnerable editable custom role (the whole vulnerability)
# -----------------------------------------------------------------------------
# THE VULNERABILITY: starting_sa is bound to this project custom role, and the
# role itself grants iam.roles.update. Because the SA holds a binding to the very
# role that lets it call roles.update, it can edit that role and add any
# permission it wants (satisfying GCPwn's "source_must_hold_custom_role"
# prerequisite for UPDATE_CUSTOM_ROLE_ADD_PERMISSIONS).
#
# The included permissions below are the STARTING set only. During the demo the
# attacker adds resourcemanager.projects.setIamPolicy out of band — that is the
# exploit, not part of setup. Terraform must NOT pre-grant setIamPolicy or
# roles/owner.
#
# iam.roles.update is the required permission. The remaining entries are the
# helpful set (validated by the permission-isolator — none are trim):
#   - iam.roles.get  : gcloud-mechanic — `gcloud iam roles update --add-permissions`
#                      reads the role first; the raw roles.patch API does not need it.
#   - resourcemanager.projects.getIamPolicy : gcloud-mechanic — `gcloud projects
#                      add-iam-policy-binding` reads project policy first; the raw
#                      setIamPolicy API does not need it. The --api-only demo also
#                      uses it for safe read-modify-write (relies on stale IAM cache
#                      after step 3b replaces the permission list).
#   - iam.roles.list, resourcemanager.projects.get : recon.
resource "google_project_iam_custom_role" "editable_role" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_editable"
  title       = "Pathfinding Labs - Editable Custom Role (vulnerable)"
  description = "Project custom role bound to starting_sa. Grants iam.roles.update on the project, so the SA can edit this very role. Recon/gcloud-mechanic permissions included per scenario.yaml permissions.helpful."
  permissions = [
    # REQUIRED — the modeled vulnerability (core attack)
    "iam.roles.update",
    # gcloud-mechanic — gcloud `iam roles update --add-permissions` reads the role
    #   first; the raw roles.patch API does not require it (--api-only passes without it)
    "iam.roles.get",
    # gcloud-mechanic — gcloud `projects add-iam-policy-binding` reads the project
    #   policy first; the raw setIamPolicy API does not require it
    "resourcemanager.projects.getIamPolicy",
    # recon — enumerate project custom roles to identify the editable one
    "iam.roles.list",
    # recon — basic project metadata retrieval
    "resourcemanager.projects.get",
  ]
}

# Bind starting_sa to the editable role. This single binding is both the
# required-permission grant AND the "attacker already holds the role" precondition.
resource "google_project_iam_member" "starting_sa_editable_role_binding" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.editable_role.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# Required APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "secretmanager" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "secretmanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# -----------------------------------------------------------------------------
# CTF Flag Resource (to-admin pattern: Secret Manager secret)
# -----------------------------------------------------------------------------
# No secretAccessor is pre-granted to starting_sa. The flag is readable only
# AFTER the attacker self-binds roles/owner during the demo — roles/owner is a
# superset that includes secretmanager.versions.access. Pre-granting access here
# would short-circuit the lab, so it is deliberately omitted.

resource "google_secret_manager_secret" "flag" {
  provider  = google.prod
  project   = var.project_id
  secret_id = "pl-${local.path_id}-flag"

  labels = {
    environment = var.environment
    scenario    = "iam-rolesupdate"
    purpose     = "ctf-flag"
  }

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "flag" {
  provider    = google.prod
  secret      = google_secret_manager_secret.flag.id
  secret_data = var.flag_value
}

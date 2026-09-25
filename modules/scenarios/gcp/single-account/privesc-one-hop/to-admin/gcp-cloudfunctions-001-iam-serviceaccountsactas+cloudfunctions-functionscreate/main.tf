terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
  }
}

locals {
  path_id = "gcp-cloudfunctions-001"
  # google_service_account.account_id is capped at 30 characters. The full
  # path_id ("gcp-cloudfunctions-001") is used everywhere else (custom role
  # IDs, GCS bucket/secret names, labels, output messages), but service
  # account account_id values need a shortened form to stay under the limit
  # across all environment name lengths (prod/dev/operations).
  sa_id_prefix = "cf001"
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
# Required APIs
# -----------------------------------------------------------------------------
# NOTE: run.googleapis.com is enabled here only because Cloud Functions gen2
# is backed by Cloud Run under the hood and the *project* must have the Cloud
# Run API enabled for gen2 deployments to succeed at all. This is project-level
# API enablement performed by the deployer/Terraform, NOT an IAM permission
# granted to starting_sa — starting_sa is never given any run.services.* or
# run.routes.* permission. The Cloud Functions v2 control plane deploys the
# underlying Cloud Run service via its own internal service agent, which is
# exactly the abstraction this scenario is demonstrating.

resource "google_project_service" "cloudfunctions" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "cloudfunctions.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "run" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "run.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "cloudbuild" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "cloudbuild.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "artifactregistry" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "artifactregistry.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "storage" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "storage.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "secretmanager" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "secretmanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# -----------------------------------------------------------------------------
# Starting Service Account (attacker's initial identity - no project role)
# -----------------------------------------------------------------------------

resource "google_service_account" "starting_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.sa_id_prefix}-start"
  display_name = "Pathfinding Labs - ${var.environment} - cloudfunctions-actas-create - Starting SA"
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
# Target Service Account (privileged - holds roles/editor on the project)
# -----------------------------------------------------------------------------

resource "google_service_account" "target_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.sa_id_prefix}-target"
  display_name = "Pathfinding Labs - ${var.environment} - cloudfunctions-actas-create - Target SA (privileged)"
}

# The target SA's own privilege - what makes running a function as it valuable.
resource "google_project_iam_member" "target_sa_admin_role" {
  provider = google.prod
  project  = var.project_id
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.target_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant #1: iam.serviceAccounts.actAs on target_sa
# -----------------------------------------------------------------------------
# Minimal custom role scoped to exactly the permission the attack needs.
# roles/iam.serviceAccountUser bundles actAs plus other permissions
# (e.g. iam.serviceAccounts.get) that aren't part of the modeled attack step —
# grant only actAs, mirroring the AWS convention of hand-written
# least-privilege custom policies.
resource "google_project_iam_custom_role" "sa_actas_minimal" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_sa_actas_min"
  title       = "Pathfinding Labs - Minimal SA ActAs"
  description = "Grants only iam.serviceAccounts.actAs - the single permission needed to attach a service account identity to a new resource (here, a Cloud Function)."
  permissions = ["iam.serviceAccounts.actAs"]
}

# THE VULNERABILITY (part 1): starting_sa holds iam.serviceAccounts.actAs on
# target_sa, allowing it to deploy a resource that runs as target_sa.
resource "google_service_account_iam_member" "vulnerable_actas_grant" {
  provider           = google.prod
  service_account_id = google_service_account.target_sa.name
  role               = google_project_iam_custom_role.sa_actas_minimal.id
  member             = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant #2: cloudfunctions.functions.create/.sourceCodeSet + run.routes.invoke
# + gcloud CLI mechanic permissions
# -----------------------------------------------------------------------------
# Core attack permissions (needed at the raw API level regardless of tooling):
#   - cloudfunctions.functions.create   — deploy the new function
#   - cloudfunctions.functions.sourceCodeSet — set the function's source
#   - run.routes.invoke                 — invoke the gen2 function's HTTPS endpoint
#     (gen2 functions are backed by Cloud Run; HTTP auth goes through Cloud Run,
#      not the Cloud Functions API — confirmed: neither functions.call nor
#      functions.invoke is needed when using identity-token + curl directly)
#
# gcloud CLI mechanic permissions (not needed with raw API calls, but required
# because gcloud functions deploy does extra preflight work):
#   - cloudfunctions.functions.get      — gcloud checks create vs update before submitting
#   - cloudfunctions.operations.get     — gcloud polls the deploy LRO (no --async flag exists)
#   - resourcemanager.projects.get      — gcloud calls GET /v1/projects/{id} unconditionally
#   - cloudbuild.builds.get             — gcloud's GetDefaultServiceAccount preflight
#   - resourcemanager.projects.getIamPolicy — gcloud validates the project IAM policy
#   - run.services.getIamPolicy         — gcloud reads Cloud Run IAM policy post-deploy
#   - run.services.setIamPolicy         — gcloud sets Cloud Run IAM for --no-allow-unauthenticated
resource "google_project_iam_custom_role" "cloudfunctions_deploy_minimal" {
  provider = google.prod
  project  = var.project_id
  role_id  = "${replace(local.path_id, "-", "_")}_cf_deploy_min"
  title    = "Pathfinding Labs - Minimal Cloud Functions Deploy"
  description = "Permissions to create a new 2nd-gen Cloud Function running as target SA and invoke it. Core: functions.create, sourceCodeSet, run.routes.invoke. CLI mechanics: functions.get, operations.get, projects.get, builds.get, getIamPolicy."
  permissions = [
    # Core attack — required at the raw API level regardless of tooling
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.sourceCodeSet",
    "run.routes.invoke",

    # gcloud CLI mechanics — not needed with raw API, but required by gcloud
    # functions deploy and gcloud functions describe:
    #   cloudfunctions.functions.get     — gcloud checks create vs update before submitting
    #   cloudfunctions.operations.get    — gcloud polls the deploy LRO (no --async flag exists)
    #   resourcemanager.projects.get     — gcloud preflight call on every command
    #   cloudbuild.builds.get            — gcloud's GetDefaultServiceAccount preflight
    #                                      on Cloud Build API (determines default build SA)
    #   resourcemanager.projects.getIamPolicy — gcloud validates IAM policy as part of
    #                                           the deploy flow
    #   run.services.getIamPolicy        — gcloud reads the Cloud Run service IAM policy
    #                                      post-deploy to verify invocation settings
    #   run.services.setIamPolicy        — gcloud sets the Cloud Run service IAM policy
    #                                      to enforce --no-allow-unauthenticated
    "cloudfunctions.functions.get",
    "cloudfunctions.operations.get",
    "resourcemanager.projects.get",
    "cloudbuild.builds.get",
    "resourcemanager.projects.getIamPolicy",
    "run.services.getIamPolicy",
    "run.services.setIamPolicy",
  ]
}

# THE VULNERABILITY (part 2): starting_sa can create, set source code for, and
# invoke Cloud Functions in this project.
resource "google_project_iam_member" "vulnerable_cloudfunctions_deploy_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cloudfunctions_deploy_minimal.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# CTF Flag Resource (to-admin pattern: Secret Manager secret)
# -----------------------------------------------------------------------------
# roles/editor (held by target_sa above) does NOT grant secretmanager.versions.access
# by itself — see the explicit secretAccessor grant below, which is what actually
# makes running as target_sa sufficient to read this flag.

resource "google_secret_manager_secret" "flag" {
  provider  = google.prod
  project   = var.project_id
  secret_id = "pl-${local.path_id}-flag"

  labels = {
    environment = var.environment
    scenario    = "cloudfunctions-actas-create"
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

# roles/editor does not include secretmanager.versions.access by design.
# Grant secretAccessor directly on the flag secret so target_sa can read it
# once the malicious function is running as target_sa and exfiltrates its
# OAuth token — this is what makes the escalation valuable.
resource "google_secret_manager_secret_iam_member" "target_sa_flag_accessor" {
  provider  = google.prod
  project   = var.project_id
  secret_id = google_secret_manager_secret.flag.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.target_sa.email}"
}

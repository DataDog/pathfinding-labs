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
# Target Service Account (privileged - holds roles/owner on the project)
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
  role     = "roles/owner"
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
# Vulnerable grant #2a: Core attack permissions (raw API minimum)
# -----------------------------------------------------------------------------
# These permissions are required regardless of tooling — even the raw Cloud
# Functions v2 REST API cannot complete the attack without them:
#   - cloudfunctions.functions.create    — deploy the new function
#   - cloudfunctions.functions.sourceCodeSet — upload the function source
#   - cloudfunctions.operations.get      — poll the async LRO until ACTIVE and
#                                          extract the Cloud Run URI from the
#                                          operation response (gen2 functions
#                                          are async; the URL is only known once
#                                          the operation finishes)
#   - run.routes.invoke                  — invoke the gen2 function's HTTPS
#                                          endpoint; gen2 HTTP auth goes through
#                                          Cloud Run IAM, not the CF API —
#                                          caller needs run.routes.invoke unless
#                                          the service is set to allow-unauthenticated
resource "google_project_iam_custom_role" "cf_deploy_required" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_cf_deploy_req"
  title       = "Pathfinding Labs - CF Deploy (Required)"
  description = "Core attack permissions: functions.create, sourceCodeSet, operations.get (LRO poll + URL extraction), run.routes.invoke. Required at the raw API level regardless of tooling."
  permissions = [
    # Core attack — required at the raw API level regardless of tooling
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.sourceCodeSet",
    # operations.get is needed even for raw API: the create call returns an async
    # LRO and the only way to know when the function is ACTIVE and to get its
    # Cloud Run URI is to poll GET /v2/{operation_name} until done=true.
    "cloudfunctions.operations.get",
    # run.routes.invoke is needed when the function is deployed with
    # --no-allow-unauthenticated (the default via gcloud). The raw API deploy
    # does not set the Cloud Run IAM policy, so the underlying Cloud Run service
    # is created without allUsers invoker — OIDC identity token invocation
    # therefore requires run.routes.invoke on the caller.
    "run.routes.invoke",
  ]
}

resource "google_project_iam_member" "vulnerable_cf_deploy_required_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cf_deploy_required.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant #2b: helpful permissions (gcloud mechanics + recon)
# -----------------------------------------------------------------------------
# NOT part of the modeled vulnerability and NOT needed by the raw Cloud
# Functions v2 REST API (--api-only mode). Two groups:
#
#   1. gcloud CLI mechanics — gcloud functions deploy issues extra preflight
#      calls beyond the raw API. Full debug-trace analysis with
#      --build-service-account revealed the minimum two-permission set:
#        - cloudfunctions.functions.get  — gcloud always calls GetFunction
#                                          before submitting (create vs. update)
#        - resourcemanager.projects.get  — gcloud calls GET /v1/projects/{id}
#                                          unconditionally as a preflight
#      ELIMINATED by --build-service-account (do NOT add here):
#        cloudbuild.builds.get, resourcemanager.projects.getIamPolicy,
#        run.services.getIamPolicy, run.services.setIamPolicy
#
#   2. Recon — the read permissions the starting SA needs to enumerate the
#      project and find the actAs target (an attacker impersonating
#      starting_sa, a learner, or the online-mode shell prepopulated as
#      starting_sa). Mirrors scenario.yaml permissions.helpful.
resource "google_project_iam_custom_role" "cf_deploy_helpful" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_cf_deploy_help"
  title       = "Pathfinding Labs - CF Deploy (Helpful: gcloud mechanics + recon)"
  description = "Helpful permissions matching scenario.yaml permissions.helpful: gcloud functions deploy mechanics (functions.get, projects.get — not needed by the raw CF v2 API) plus recon to find the actAs target. Not part of the modeled vulnerability."
  permissions = [
    # gcloud functions deploy mechanics — gcloud-only, not needed by the raw CF v2 API
    "cloudfunctions.functions.get",
    "resourcemanager.projects.get",
    # Recon — enumerate service accounts and inspect their IAM bindings to
    # find the actAs target
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.getIamPolicy",
  ]
}

resource "google_project_iam_member" "vulnerable_cf_deploy_helpful_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cf_deploy_helpful.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# CTF Flag Resource (to-admin pattern: Secret Manager secret)
# -----------------------------------------------------------------------------
# roles/owner (held by target_sa above) includes secretmanager.versions.access,
# so running as target_sa is sufficient to read this flag — no extra grant needed.

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


terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
  }
}

locals {
  path_id = "gcp-cloudrun-001"
  # google_service_account.account_id is capped at 30 characters. The full
  # path_id ("gcp-cloudrun-001") is used everywhere else (custom role IDs,
  # secret names, labels, output messages), but service account account_id
  # values need a shortened form to stay under the limit across all
  # environment name lengths (prod/dev/operations).
  sa_id_prefix = "cr001"
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
# Deliberately NOT enabled: cloudbuild.googleapis.com and
# artifactregistry.googleapis.com. The whole point of this technique is that
# deploying a Cloud Run service from a PUBLIC Docker Hub image requires
# neither — Cloud Run's service agent pulls the public image server-side.
# This is the project-level API enablement performed by the deployer/
# Terraform, NOT an IAM permission granted to starting_sa.

resource "google_project_service" "run" {
  provider                   = google.prod
  project                    = var.project_id
  service                    = "run.googleapis.com"
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
  display_name = "Pathfinding Labs - ${var.environment} - cloudrun-actas-create - Starting SA"
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
  display_name = "Pathfinding Labs - ${var.environment} - cloudrun-actas-create - Target SA (privileged)"
}

# The target SA's own privilege - what makes running a Cloud Run service as
# it valuable.
resource "google_project_iam_member" "target_sa_admin_role" {
  provider = google.prod
  project  = var.project_id
  role     = "roles/owner"
  member   = "serviceAccount:${google_service_account.target_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant #1: Core attack permissions (VERIFIED raw-API minimum —
# empirically isolated by the scenario-permission-isolator-gcp agent via
# leave-one-out terraform apply + demo cycles in both gcloud and --api-only
# modes; every removal below was individually verified to break the demo)
# -----------------------------------------------------------------------------
# The GCP analog of iam:PassRole + compute:CreateFunction-style escalation:
# the starting SA can deploy a NEW compute resource (a Cloud Run service)
# bound to run as the privileged target SA. Minimal CUSTOM role — never
# roles/iam.serviceAccountUser (which bundles actAs with other permissions)
# and never roles/run.admin (which bundles far more than create/invoke).
#
# VERIFIED required set (raw API minimum, 2026-11-01 isolation run):
#   - iam.serviceAccounts.actAs  — required at service creation time when the
#                                  service is bound to target_sa (the GCP
#                                  analog of iam:PassRole; actas_required).
#                                  Lives in its own role bound ONLY on
#                                  target_sa (sa_actas_minimal below)
#   - run.services.create        — deploy the new Cloud Run service
#   - run.services.get           — fetch the new service's URL (raw API)
#                                  and gcloud's readiness/preflight polling
#   - run.operations.get         — poll the async LRO that services.create
#                                  returns — the only way to know when the
#                                  deploy finished (mirrors cf001's
#                                  cloudfunctions.operations.get)
#   - logging.logEntries.list    — read the exfiltrated token from Cloud Run
#                                  logs: the exfil channel of the technique
#                                  (gcpwn --exfil-mode logs); needed by the
#                                  raw API (POST entries:list) too
#
# Verified NOT needed (removed during isolation): run.services.update
# (gcloud re-deploy to an existing service only), run.routes.invoke (invoke
# returns 403 without it, but the demo tolerates it — the deploy-time
# readiness instance already exfiltrates the token), resourcemanager.
# projects.get, iam.serviceAccounts.get, run.services.setIamPolicy,
# run.services.getIamPolicy (not needed even on the re-deploy path).
resource "google_project_iam_custom_role" "sa_actas_minimal" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_sa_actas_min"
  title       = "Pathfinding Labs - Minimal SA ActAs"
  description = "Grants only iam.serviceAccounts.actAs - the single permission needed to attach a service account identity to a new resource (here, a Cloud Run service). Bound on target_sa only, never at project level."
  permissions = ["iam.serviceAccounts.actAs"]
}

# THE VULNERABILITY (part 1, SA-scoped): starting_sa holds
# iam.serviceAccounts.actAs on target_sa ONLY, allowing it to deploy a Cloud
# Run service that runs as target_sa. Bound on the target SA rather than at
# project level so starting_sa cannot act as any other SA in the project
# (mirrors gcp-cloudfunctions-001 and scenario.yaml's resource scoping).
resource "google_service_account_iam_member" "vulnerable_actas_grant" {
  provider           = google.prod
  service_account_id = google_service_account.target_sa.name
  role               = google_project_iam_custom_role.sa_actas_minimal.id
  member             = "serviceAccount:${google_service_account.starting_sa.email}"
}

resource "google_project_iam_custom_role" "cr_deploy_required" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_cr_deploy_req"
  title       = "Pathfinding Labs - CR Deploy (Required)"
  description = "Verified raw-API minimum (excluding actAs, which is bound separately on target_sa): run.services.create/get + run.operations.get + logging.logEntries.list (logs exfil channel). Required to deploy a new Cloud Run service and recover its exfiltrated token."
  permissions = [
    "run.services.create",
    "run.services.get",
    "run.operations.get",
    "logging.logEntries.list",
  ]
}

# THE VULNERABILITY (part 2, project-scoped): starting_sa holds the Cloud Run
# deploy + log-read permissions at project level. Combined with part 1, this
# lets it create a service bound to target_sa and read the token it leaks.
resource "google_project_iam_member" "vulnerable_cr_deploy_required_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cr_deploy_required.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant #2: helpful permissions (verified gcloud mechanics + recon)
# -----------------------------------------------------------------------------
# NOT part of the modeled vulnerability and NOT needed by the raw Cloud Run
# API (--api-only mode) for a FRESH deploy. Two groups (verified by the
# permission isolation run, 2026-11-01):
#
#   1. gcloud CLI mechanics — needed only when re-running `gcloud run deploy`
#      against the deterministic service name left behind by a prior demo
#      run (fresh deploys need only the required set above):
#        - run.services.update     — gcloud re-deploy to an EXISTING service
#                                   takes the update path (fresh --api-only
#                                   and gcloud deploys verified to succeed
#                                   without it)
#
#   2. Practical/recon — the invoke trigger and enumeration:
#        - run.routes.invoke        — invoke the deployed service for a
#                                   fresh per-request exfil (gcpwn --invoke);
#                                   without it the invoke returns 403, but
#                                   the deploy-time readiness instance
#                                   already exfiltrates the token
#        - iam.serviceAccounts.list / getIamPolicy — enumerate service
#                                   accounts and their actAs grants to find
#                                   the target
#        - run.services.list        — enumerate existing Cloud Run services
#
#   Verified NOT needed at all (removed during isolation):
#     resourcemanager.projects.get, iam.serviceAccounts.get,
#     run.services.setIamPolicy, run.services.getIamPolicy — gcloud run
#     deploy with --no-allow-unauthenticated issues none of these, not even
#     on the re-deploy path.
resource "google_project_iam_custom_role" "cr_deploy_helpful" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_cr_deploy_help"
  title       = "Pathfinding Labs - CR Deploy (Helpful: gcloud mechanics + recon)"
  description = "Verified helpful permissions matching scenario.yaml permissions.helpful: gcloud re-deploy mechanics (run.services.update) plus the invoke trigger and recon. Not part of the modeled vulnerability."
  permissions = [
    "run.services.update",
    "run.routes.invoke",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.getIamPolicy",
    "run.services.list",
  ]
}

resource "google_project_iam_member" "vulnerable_cr_deploy_helpful_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cr_deploy_helpful.id
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
    scenario    = "cloudrun-actas-create"
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


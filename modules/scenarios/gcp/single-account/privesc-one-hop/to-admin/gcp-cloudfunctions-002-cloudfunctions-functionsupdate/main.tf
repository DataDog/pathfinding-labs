terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  path_id = "gcp-cloudfunctions-002"
  # google_service_account.account_id is capped at 30 characters. The full
  # path_id ("gcp-cloudfunctions-002") is used everywhere else (custom role
  # IDs, GCS bucket/secret names, labels, output messages), but service
  # account account_id values need a shortened form to stay under the limit
  # across all environment name lengths (prod/dev/operations).
  sa_id_prefix = "cf002"
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

# Used to obtain the project number, which is needed to construct the
# Cloud Build default service account email for the source bucket grant.
data "google_project" "project" {
  provider   = google.prod
  project_id = var.project_id
}

# -----------------------------------------------------------------------------
# Required APIs
# -----------------------------------------------------------------------------
# NOTE: run.googleapis.com is enabled here because Cloud Functions gen2 is
# backed by Cloud Run under the hood — the project must have the Cloud Run API
# enabled for gen2 deployments to succeed at all. This is project-level API
# enablement, NOT an IAM permission granted to starting_sa. starting_sa is
# given run.routes.invoke so it can invoke the updated function's HTTPS
# endpoint; the Cloud Functions v2 control plane deploys and manages the
# underlying Cloud Run service via its own internal service agent.

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
# Starting Service Account (attacker's initial identity — no project role)
# -----------------------------------------------------------------------------

resource "google_service_account" "starting_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.sa_id_prefix}-start"
  display_name = "Pathfinding Labs - ${var.environment} - cloudfunctions-functionsupdate - Starting SA"
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
# Target Service Account (privileged — holds roles/editor on the project)
# -----------------------------------------------------------------------------

resource "google_service_account" "target_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.sa_id_prefix}-target"
  display_name = "Pathfinding Labs - ${var.environment} - cloudfunctions-functionsupdate - Target SA (privileged)"
}

# The target SA's own privilege — what makes running a function as it valuable.
resource "google_project_iam_member" "target_sa_admin_role" {
  provider = google.prod
  project  = var.project_id
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.target_sa.email}"
}

# -----------------------------------------------------------------------------
# Vulnerable grant: cloudfunctions.functions.update/.sourceCodeSet + run.routes.invoke
# + gcloud CLI mechanic permissions
# -----------------------------------------------------------------------------
# Core attack permissions (needed at the raw API level regardless of tooling):
#   - cloudfunctions.functions.update    — replace the function's code/config
#   - cloudfunctions.functions.sourceCodeSet — upload a new source archive
#   - run.routes.invoke                  — invoke the gen2 function's HTTPS endpoint
#     (gen2 functions are backed by Cloud Run; invocation auth is checked by
#      Cloud Run, not the Cloud Functions API)
#
# gcloud CLI mechanic permissions (not needed with raw API calls, but required
# because gcloud functions deploy does extra preflight work):
#   - cloudfunctions.functions.get       — gcloud reads current config before submitting update
#   - cloudfunctions.operations.get      — gcloud polls the update LRO (no --async flag for gen2)
#   - resourcemanager.projects.get       — gcloud calls GET /v1/projects/{id} unconditionally
#
# GCP's UpdateFunction API always checks iam.serviceAccounts.actAs on the
# function's existing build SA and runtime SA — even for code-only updates.
# Both SAs are target_sa, so actAs on target_sa is required.
# The distinction from cf-001 (create): attacker targets an EXISTING function
# that already runs as target_sa. Only cloudfunctions.functions.update is
# needed (not functions.create), but actAs on target_sa is still required.
resource "google_project_iam_custom_role" "cf_update_minimal" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "gcp_cloudfunctions_002_cf_update_min"
  title       = "Pathfinding Labs - Minimal Cloud Functions Update"
  description = "Permissions to update an existing 2nd-gen Cloud Function's code and invoke it. Core: functions.update, sourceCodeSet, run.routes.invoke. CLI mechanics: functions.get, operations.get, projects.get, builds.get, getIamPolicy."
  permissions = [
    # Core attack — required at the raw API level regardless of tooling
    "cloudfunctions.functions.update",
    "cloudfunctions.functions.sourceCodeSet",
    "run.routes.invoke",

    # gcloud CLI mechanics — not needed with raw API, but required by gcloud
    # functions deploy and gcloud functions describe:
    #   cloudfunctions.functions.get     — gcloud reads current config before update
    #   cloudfunctions.operations.get    — gcloud polls the update LRO
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

resource "google_project_iam_member" "vulnerable_cloudfunctions_update_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.cf_update_minimal.id
  member   = "serviceAccount:${google_service_account.starting_sa.email}"
}

# THE VULNERABILITY: starting_sa holds actAs on target_sa (serviceAccountUser)
# AND can update existing Cloud Functions. The victim function already runs as
# target_sa. By updating the code while keeping target_sa attached, the attacker
# turns the existing privileged function into a metadata-server token exfiltrator.
resource "google_service_account_iam_member" "vulnerable_actas_grant" {
  provider           = google.prod
  service_account_id = google_service_account.target_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.starting_sa.email}"
}

# -----------------------------------------------------------------------------
# Pre-deployed victim Cloud Function (the "existing prod function" the attacker
# will hijack — Terraform deploys it with benign hello-world code)
# -----------------------------------------------------------------------------

# GCS bucket to stage the hello-world source zip during initial deployment.
# The bucket name includes project_id to ensure global uniqueness while
# remaining identifiable.
resource "google_storage_bucket" "source" {
  provider                    = google.prod
  project                     = var.project_id
  name                        = "pl-cf002-src-${var.project_id}-${var.resource_suffix}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = var.environment
    scenario    = "cloudfunctions-functionsupdate"
    purpose     = "function-source-staging"
  }

  depends_on = [google_project_service.storage]
}

# Benign hello-world source for the victim function. The attacker replaces
# this with a token-exfiltration payload during the attack.
data "archive_file" "victim_source" {
  type        = "zip"
  output_path = "${path.module}/.build/victim_source.zip"

  source {
    content  = <<-PY
def hello_world(request):
    return ("Hello, World!", 200, {"Content-Type": "text/plain"})
PY
    filename = "main.py"
  }

  source {
    content  = "functions-framework==3.*\n"
    filename = "requirements.txt"
  }
}

# Upload the hello-world zip to the staging bucket so Cloud Functions can
# use it as the initial build source.
resource "google_storage_bucket_object" "victim_source" {
  provider = google.prod
  name     = "victim-hello-world-${var.resource_suffix}.zip"
  bucket   = google_storage_bucket.source.name
  source   = data.archive_file.victim_source.output_path
}

# The Cloud Build default service account needs objectViewer on the source
# bucket to pull the zip during the function build. The SA email format is
# "{project_number}@cloudbuild.gserviceaccount.com".
# depends_on ensures the Cloud Build API is enabled (and thus the default SA
# exists) before the binding is created.
resource "google_storage_bucket_iam_member" "cloudbuild_sa_source_viewer" {
  provider = google.prod
  bucket   = google_storage_bucket.source.name
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [google_project_service.cloudbuild]
}

# The victim 2nd-gen Cloud Function. This represents the "existing production
# function" in the scenario — it runs as target_sa from the moment it is
# deployed by Terraform. The attacker only needs to replace its code.
resource "google_cloudfunctions2_function" "victim" {
  provider = google.prod
  project  = var.project_id
  name     = "pl-cf002-victim-${var.resource_suffix}"
  location = var.region

  labels = {
    environment = var.environment
    scenario    = "cloudfunctions-functionsupdate"
    purpose     = "victim-function"
  }

  build_config {
    runtime     = "python312"
    entry_point = "hello_world"

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.victim_source.name
      }
    }

    # target_sa is used as the build SA so Cloud Build inherits editor access
    # to Artifact Registry, GCS, and the build environment without extra grants.
    service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.target_sa.email}"
  }

  service_config {
    min_instance_count    = 0
    max_instance_count    = 1
    available_memory      = "128Mi"
    timeout_seconds       = 60
    service_account_email = google_service_account.target_sa.email
    ingress_settings      = "ALLOW_ALL"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.run,
    google_project_service.cloudbuild,
    google_project_service.artifactregistry,
    google_project_service.storage,
    google_storage_bucket_iam_member.cloudbuild_sa_source_viewer,
    google_project_iam_member.target_sa_admin_role,
  ]
}

# -----------------------------------------------------------------------------
# CTF Flag Resource (to-admin pattern: Secret Manager secret)
# -----------------------------------------------------------------------------
# roles/editor (held by target_sa) does NOT grant secretmanager.versions.access
# by itself — see the explicit secretAccessor grant below, which is what
# actually makes running as target_sa sufficient to read this flag.

resource "google_secret_manager_secret" "flag" {
  provider  = google.prod
  project   = var.project_id
  secret_id = "pl-${local.path_id}-flag"

  labels = {
    environment = var.environment
    scenario    = "cloudfunctions-functionsupdate"
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
# once the attacker's malicious function runs as target_sa and the attacker
# uses target_sa's stolen OAuth token to access Secret Manager.
resource "google_secret_manager_secret_iam_member" "target_sa_flag_accessor" {
  provider  = google.prod
  project   = var.project_id
  secret_id = google_secret_manager_secret.flag.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.target_sa.email}"
}

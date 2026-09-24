terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
  }
}

locals {
  path_id = "gcp-iam-001"
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
# Starting Service Account (attacker's initial identity - no project role)
# -----------------------------------------------------------------------------

resource "google_service_account" "starting_sa" {
  provider     = google.prod
  project      = var.project_id
  account_id   = "pl-${var.environment}-${local.path_id}-start"
  display_name = "Pathfinding Labs - ${var.environment} - iam-serviceaccountsgetaccesstoken - Starting SA"
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
  account_id   = "pl-${var.environment}-${local.path_id}-target"
  display_name = "Pathfinding Labs - ${var.environment} - iam-serviceaccountsgetaccesstoken - Target SA (privileged)"
}

# Minimal custom role scoped to exactly the permission the attack needs.
# Mirrors the AWS convention of hand-written least-privilege custom policies
# rather than attaching a broad managed policy/predefined role — the vulnerable
# principal here should hold only iam.serviceAccounts.getAccessToken, not the
# signBlob/signJwt/implicitDelegation permissions roles/iam.serviceAccountTokenCreator
# also bundles.
resource "google_project_iam_custom_role" "sa_token_creator_minimal" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_sa_token_creator_min"
  title       = "Pathfinding Labs - Minimal SA Token Creator"
  description = "Grants only iam.serviceAccounts.getAccessToken - the single permission needed to impersonate a service account and mint an OAuth access token."
  permissions = ["iam.serviceAccounts.getAccessToken"]
}

# THE VULNERABILITY: starting_sa holds iam.serviceAccounts.getAccessToken on
# target_sa (via the minimal custom role above), allowing it to call the
# generateAccessToken API and act as target_sa, which itself holds
# roles/editor on the project.
resource "google_service_account_iam_member" "vulnerable_impersonation_grant" {
  provider           = google.prod
  service_account_id = google_service_account.target_sa.name
  role               = google_project_iam_custom_role.sa_token_creator_minimal.id
  member             = "serviceAccount:${google_service_account.starting_sa.email}"
}

# The target SA's own privilege - what makes impersonating it valuable.
resource "google_project_iam_member" "target_sa_admin_role" {
  provider = google.prod
  project  = var.project_id
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.target_sa.email}"
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
# roles/editor (held by target_sa above) does NOT grant secretmanager.versions.access
# by itself — see the explicit secretAccessor grant below, which is what actually
# makes impersonating target_sa sufficient to read this flag.

resource "google_secret_manager_secret" "flag" {
  provider  = google.prod
  project   = var.project_id
  secret_id = "pl-${local.path_id}-flag"

  labels = {
    environment = var.environment
    scenario    = "iam-serviceaccountsgetaccesstoken"
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
# when impersonated — this is what makes the escalation valuable.
resource "google_secret_manager_secret_iam_member" "target_sa_flag_accessor" {
  provider  = google.prod
  project   = var.project_id
  secret_id = google_secret_manager_secret.flag.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.target_sa.email}"
}

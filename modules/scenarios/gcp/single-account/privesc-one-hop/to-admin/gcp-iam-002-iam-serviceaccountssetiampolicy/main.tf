terraform {
  required_providers {
    google = {
      source                = "hashicorp/google"
      configuration_aliases = [google.prod]
    }
  }
}

locals {
  path_id = "gcp-iam-002"
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
  display_name = "Pathfinding Labs - ${var.environment} - iam-serviceaccountssetiampolicy - Starting SA"
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
  display_name = "Pathfinding Labs - ${var.environment} - iam-serviceaccountssetiampolicy - Target SA (privileged)"
}

# Minimal custom role scoped to exactly the permission the attack needs.
# Mirrors the AWS convention of hand-written least-privilege custom policies
# rather than attaching a broad predefined role — the vulnerable principal here
# should hold only iam.serviceAccounts.setIamPolicy, not the SA-admin,
# key-management, or actAs permissions that roles/iam.serviceAccountAdmin bundles.
resource "google_project_iam_custom_role" "sa_setiampolicy_minimal" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_sa_setiampolicy_min"
  title       = "Pathfinding Labs - Minimal SA setIamPolicy"
  description = "Grants only iam.serviceAccounts.setIamPolicy - the single permission needed to rewrite a service account's IAM policy (e.g. to grant oneself tokenCreator on it)."
  permissions = ["iam.serviceAccounts.setIamPolicy"]
}

# THE VULNERABILITY: starting_sa holds iam.serviceAccounts.setIamPolicy on
# target_sa (via the minimal custom role above). This lets it rewrite target_sa's
# IAM policy to grant itself roles/iam.serviceAccountTokenCreator, then mint an
# access token as target_sa — which itself holds roles/editor on the project.
# Terraform only establishes this capability; the demo performs the self-grant
# out of band (that is the exploit, not part of setup).
resource "google_service_account_iam_member" "vulnerable_setiampolicy_grant" {
  provider           = google.prod
  service_account_id = google_service_account.target_sa.name
  role               = google_project_iam_custom_role.sa_setiampolicy_minimal.id
  member             = "serviceAccount:${google_service_account.starting_sa.email}"
}

# The target SA's own privilege - what makes impersonating it valuable.
resource "google_project_iam_member" "target_sa_editor_role" {
  provider = google.prod
  project  = var.project_id
  role     = "roles/editor"
  member   = "serviceAccount:${google_service_account.target_sa.email}"
}

# -----------------------------------------------------------------------------
# Helpful permissions (granted to starting_sa so it can do recon itself)
# -----------------------------------------------------------------------------
# NOT part of the modeled vulnerability — these mirror scenario.yaml's
# permissions.helpful. Verified by the permission-isolator against a live deploy.
#
# Two categories:
#   gcloud-mechanic: required by gcloud iam service-accounts add-iam-policy-binding
#     (reads existing SA IAM policy before merging). Raw setIamPolicy does not need it.
#   recon: lets the starting SA enumerate project SAs to identify the target.
#
# Trimmed from the original Phase-A list:
#   iam.serviceAccounts.get         — not called by any demo step in either mode
#   resourcemanager.projects.get    — not needed by either mode (demo passes without it)
resource "google_project_iam_custom_role" "sa_recon_helpful" {
  provider    = google.prod
  project     = var.project_id
  role_id     = "${replace(local.path_id, "-", "_")}_sa_recon_help"
  title       = "Pathfinding Labs - SA Recon (Helpful)"
  description = "Recon + gcloud-mechanic permissions matching scenario.yaml permissions.helpful. Not part of the modeled vulnerability."
  permissions = [
    # gcloud CLI mechanic — required by gcloud iam service-accounts add-iam-policy-binding,
    # which reads the existing SA IAM policy (getIamPolicy) before merging and writing back.
    # The raw setIamPolicy API constructs the new policy from scratch — no prior read needed.
    "iam.serviceAccounts.getIamPolicy",
    # recon — so the starting SA can enumerate service accounts in the project to find the target.
    # demo_attack.sh Step 2b calls gcloud iam service-accounts list; the demo continues
    # gracefully if unavailable, but granting it makes the lab experience authentic.
    "iam.serviceAccounts.list",
  ]
}

resource "google_project_iam_member" "helpful_recon_grant" {
  provider = google.prod
  project  = var.project_id
  role     = google_project_iam_custom_role.sa_recon_helpful.id
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
# roles/editor (held by target_sa above) does NOT grant secretmanager.versions.access
# by itself — see the explicit secretAccessor grant below, which is what actually
# makes impersonating target_sa sufficient to read this flag.

resource "google_secret_manager_secret" "flag" {
  provider  = google.prod
  project   = var.project_id
  secret_id = "pl-${local.path_id}-flag"

  labels = {
    environment = var.environment
    scenario    = "iam-serviceaccountssetiampolicy"
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

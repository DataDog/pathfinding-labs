output "starting_sa_email" {
  description = "Email of the starting service account for this attack path. Demo scripts impersonate this SA using '--impersonate-service-account' — no static key required."
  value       = google_service_account.starting_sa.email
}

output "starting_sa_id" {
  description = "Fully qualified resource name of the starting service account"
  value       = google_service_account.starting_sa.name
}

output "deployer_email" {
  description = "Email of the identity that ran terraform apply (auto-detected from ADC). This identity holds serviceAccountTokenCreator on starting_sa."
  value       = data.google_client_openid_userinfo.deployer.email
}

output "target_sa_email" {
  description = "Email of the privileged target service account that the malicious Cloud Run service runs as"
  value       = google_service_account.target_sa.email
}

output "target_sa_id" {
  description = "Fully qualified resource name of the privileged target service account"
  value       = google_service_account.target_sa.name
}

output "project_id" {
  description = "GCP project ID the scenario resources live in (the demo needs it for gcloud run deploy)"
  value       = var.project_id
}

output "region" {
  description = "GCP region the malicious Cloud Run service will be deployed into by the demo"
  value       = var.region
}

output "attack_path" {
  description = "Human-readable summary of the attack path"
  value       = "starting_sa -> (iam.serviceAccounts.actAs on target_sa + run.services.create via minimal custom role) -> deploys a new Cloud Run service bound to target_sa from a public Docker Hub image (no Artifact Registry access needed) -> invokes it to execute arbitrary code -> exfiltrates target_sa's OAuth access token from the metadata server -> (roles/editor) -> Project Admin"
}

output "flag_secret_id" {
  description = "Secret Manager secret_id holding the CTF flag, readable via secretmanager.versions.access once acting as target_sa"
  value       = google_secret_manager_secret.flag.secret_id
}

output "flag_secret_name" {
  description = "Fully qualified Secret Manager resource name of the CTF flag secret"
  value       = google_secret_manager_secret.flag.name
}

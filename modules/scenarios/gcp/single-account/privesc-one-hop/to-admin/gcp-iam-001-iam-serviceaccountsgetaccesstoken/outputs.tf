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
  description = "Email of the privileged target service account"
  value       = google_service_account.target_sa.email
}

output "target_sa_id" {
  description = "Fully qualified resource name of the privileged target service account"
  value       = google_service_account.target_sa.name
}

output "attack_path" {
  description = "Human-readable summary of the attack path"
  value       = "starting_sa -> (iam.serviceAccounts.getAccessToken via minimal custom role) -> target_sa -> (roles/editor) -> Project Admin"
}

output "flag_secret_id" {
  description = "Secret Manager secret_id holding the CTF flag, readable via secretmanager.versions.access once impersonating target_sa"
  value       = google_secret_manager_secret.flag.secret_id
}

output "flag_secret_name" {
  description = "Fully qualified Secret Manager resource name of the CTF flag secret"
  value       = google_secret_manager_secret.flag.name
}

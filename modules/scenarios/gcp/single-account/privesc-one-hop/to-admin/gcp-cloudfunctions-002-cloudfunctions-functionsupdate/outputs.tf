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
  description = "Email of the privileged target service account that the victim Cloud Function already runs as"
  value       = google_service_account.target_sa.email
}

output "target_sa_id" {
  description = "Fully qualified resource name of the privileged target service account"
  value       = google_service_account.target_sa.name
}

output "region" {
  description = "GCP region the victim Cloud Function and staging bucket are deployed into"
  value       = var.region
}

output "victim_function_name" {
  description = "Name of the pre-deployed victim Cloud Function. Demo scripts update this function's code with a token-exfiltration payload."
  value       = google_cloudfunctions2_function.victim.name
}

output "attack_path" {
  description = "Human-readable summary of the attack path"
  value       = "starting_sa -> (cloudfunctions.functions.update + cloudfunctions.functions.sourceCodeSet via minimal custom role + iam.serviceAccounts.actAs on target_sa via roles/iam.serviceAccountUser) -> replaces code of existing 2nd-gen Cloud Function '${google_cloudfunctions2_function.victim.name}' that already runs as target_sa -> invokes updated function via run.routes.invoke -> exfiltrates target_sa's OAuth access token from the function's metadata server -> (roles/editor) -> Project Admin"
}

output "flag_secret_id" {
  description = "Secret Manager secret_id holding the CTF flag, readable via secretmanager.versions.access once acting as target_sa"
  value       = google_secret_manager_secret.flag.secret_id
}

output "flag_secret_name" {
  description = "Fully qualified Secret Manager resource name of the CTF flag secret"
  value       = google_secret_manager_secret.flag.name
}

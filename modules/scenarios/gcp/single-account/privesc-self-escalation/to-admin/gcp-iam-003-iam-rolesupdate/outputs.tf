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

output "editable_role_id" {
  description = "Fully qualified ID (projects/{project}/roles/{id}) of the vulnerable editable custom role that starting_sa is bound to and can update."
  value       = google_project_iam_custom_role.editable_role.id
}

output "attack_path" {
  description = "Human-readable summary of the attack path"
  value       = "starting_sa (bound to a project custom role that includes iam.roles.update) -> (iam.roles.update adds resourcemanager.projects.setIamPolicy to that role) -> (resourcemanager.projects.setIamPolicy self-binds roles/owner) -> Project Admin + flag"
}

output "flag_secret_id" {
  description = "Secret Manager secret_id holding the CTF flag, readable via secretmanager.versions.access once the attacker self-binds roles/owner"
  value       = google_secret_manager_secret.flag.secret_id
}

output "flag_secret_name" {
  description = "Fully qualified Secret Manager resource name of the CTF flag secret"
  value       = google_secret_manager_secret.flag.name
}

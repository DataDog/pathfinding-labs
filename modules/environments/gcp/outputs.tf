output "deployer_email" {
  description = "Email of the identity that ran terraform apply (auto-detected from ADC)"
  value       = data.google_client_openid_userinfo.deployer.email
}

output "admin_cleanup_service_account_email" {
  description = "Email of the admin cleanup service account. Demo/cleanup scripts impersonate this SA using '--impersonate-service-account' with the deployer's ADC — no static key required."
  value       = google_service_account.admin_cleanup.email
}

output "readonly_service_account_email" {
  description = "Email of the readonly service account. Demo scripts impersonate this SA using '--impersonate-service-account' with the deployer's ADC — no static key required."
  value       = google_service_account.readonly.email
}

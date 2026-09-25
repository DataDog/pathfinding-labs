output "resource_suffix" {
  description = "Random suffix used for globally namespaced resources"
  value       = random_string.resource_suffix.result
}

output "gcp_project_id" {
  description = "GCP project ID for the prod environment — used by demo scripts to look up the active project without re-reading terraform.tfvars"
  value       = var.prod_project_id
}

output "gcp_prod_environment" {
  description = "Admin cleanup and readonly service account details for the prod environment"
  value = var.enable_gcp_prod_environment ? {
    deployer_email                       = module.gcp_prod_environment[0].deployer_email
    admin_cleanup_service_account_email  = module.gcp_prod_environment[0].admin_cleanup_service_account_email
    readonly_service_account_email       = module.gcp_prod_environment[0].readonly_service_account_email
  } : null
  sensitive = true
}

output "gcp_dev_environment" {
  description = "Admin cleanup and readonly service account details for the dev environment"
  value = var.enable_gcp_dev_environment ? {
    deployer_email                       = module.gcp_dev_environment[0].deployer_email
    admin_cleanup_service_account_email  = module.gcp_dev_environment[0].admin_cleanup_service_account_email
    readonly_service_account_email       = module.gcp_dev_environment[0].readonly_service_account_email
  } : null
  sensitive = true
}

output "gcp_ops_environment" {
  description = "Admin cleanup and readonly service account details for the ops environment"
  value = var.enable_gcp_ops_environment ? {
    deployer_email                       = module.gcp_ops_environment[0].deployer_email
    admin_cleanup_service_account_email  = module.gcp_ops_environment[0].admin_cleanup_service_account_email
    readonly_service_account_email       = module.gcp_ops_environment[0].readonly_service_account_email
  } : null
  sensitive = true
}

##############################################################################
# GCP SCENARIO OUTPUTS
##############################################################################

output "gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate" {
  description = "All outputs for gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate one-hop to-admin scenario"
  value = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate ? {
    starting_sa_email  = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].starting_sa_email
    starting_sa_id     = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].starting_sa_id
    deployer_email     = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].deployer_email
    target_sa_email    = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].target_sa_email
    target_sa_id       = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].target_sa_id
    region             = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].region
    attack_path        = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].attack_path
    flag_secret_id     = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].flag_secret_id
    flag_secret_name   = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate[0].flag_secret_name
  } : null
  sensitive = true
}

output "gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate" {
  description = "All outputs for gcp-cloudfunctions-002-cloudfunctions-functionsupdate one-hop to-admin scenario"
  value = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate ? {
    starting_sa_email    = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].starting_sa_email
    starting_sa_id       = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].starting_sa_id
    deployer_email       = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].deployer_email
    target_sa_email      = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].target_sa_email
    target_sa_id         = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].target_sa_id
    region               = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].region
    victim_function_name = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].victim_function_name
    attack_path          = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].attack_path
    flag_secret_id       = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].flag_secret_id
    flag_secret_name     = module.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate[0].flag_secret_name
  } : null
  sensitive = true
}

output "gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken" {
  description = "All outputs for gcp-iam-001-iam-serviceaccountsgetaccesstoken one-hop to-admin scenario"
  value = var.enable_gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken ? {
    starting_sa_email = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].starting_sa_email
    starting_sa_id    = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].starting_sa_id
    deployer_email    = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].deployer_email
    target_sa_email   = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].target_sa_email
    target_sa_id      = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].target_sa_id
    attack_path       = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].attack_path
    flag_secret_id    = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].flag_secret_id
    flag_secret_name  = module.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken[0].flag_secret_name
  } : null
  sensitive = true
}

##############################################################################
# ACCOUNT CONFIGURATION
##############################################################################

variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "dev_account_aws_profile" {
  description = "AWS profile for dev environment (leave empty to use prod profile)"
  default     = ""
}

variable "operations_account_aws_profile" {
  description = "AWS profile for operations account (leave empty to use prod profile)"
  default     = ""
}

variable "prod_account_aws_profile" {
  description = "AWS profile for prod account"
  default     = "pl-pathfinding-starting-user-prod"
}

variable "prod_account_id" {
  description = "The account id of the prod account (optional - auto-derived from profile if not specified)"
  type        = string
  default     = ""
}

variable "operations_account_id" {
  description = "The account id of the operations account (optional - auto-derived from profile if not specified)"
  type        = string
  default     = ""
}

variable "dev_account_id" {
  description = "The account id of the dev account (optional - auto-derived from profile if not specified)"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "The github repo for the OIDC-GitHub challenge"
  type        = string
  default     = null
}

##############################################################################
# ENVIRONMENT ENABLEMENT
##############################################################################

variable "enable_prod_environment" {
  description = "Enable the prod environment"
  type        = bool
  default     = true
}

variable "enable_dev_environment" {
  description = "Enable the dev environment (requires dev_account_id and dev_account_aws_profile)"
  type        = bool
  default     = false
}

variable "enable_ops_environment" {
  description = "Enable the ops environment (requires operations_account_id and operations_account_aws_profile)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT SELF-ESCALATION TO-ADMIN SCENARIOS
##############################################################################

variable "enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-005-iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-009-iam-attachrolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-001-iam-createpolicyversion"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_007_iam_putuserpolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-007-iam-putuserpolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-011-iam-putgrouppolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-013-iam-addusertogroup"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-008-iam-attachuserpolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-010-iam-attachgrouppolicy"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT SELF-ESCALATION TO-BUCKET SCENARIOS
##############################################################################

variable "enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-bucket → iam-005 (iam-putrolepolicy)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-bucket → iam-009-iam-attachrolepolicy"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-ADMIN SCENARIOS
##############################################################################

variable "enable_single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-019-iam-attachrolepolicy+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_014_iam_attachrolepolicy_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-014-iam-attachrolepolicy+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_015_iam_attachuserpolicy_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-015-iam-attachuserpolicy+iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_apprunner_002_apprunner_updateservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → apprunner-002-apprunner-updateservice"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-002-iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-004-iam-createloginprofile (Pathfinding.cloud: iam-004)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-003-iam-deleteaccesskey+createaccesskey (Pathfinding.cloud: iam-003)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_020_iam_createpolicyversion_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-020-iam-createpolicyversion+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-016 → iam-createpolicyversion+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_006_iam_updateloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-006-iam-updateloginprofile"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_apprunner_001_iam_passrole_apprunner_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → apprunner-001-iam-passrole+apprunner-createservice (Pathfinding.cloud: apprunner-001)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter" {
  description = "Enable: single-account → privesc → one-hop → to-admin → bedrock-001-iam-passrole+bedrockagentcore-codeinterpreter (Pathfinding.cloud: bedrock-001)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke" {
  description = "Enable: single-account → privesc → one-hop → to-admin → bedrock-002-bedrockagentcore-startsession+invoke (Pathfinding.cloud: bedrock-002)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-001-iam-passrole+ec2-runinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-004-iam-passrole+ec2-requestspotinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-005 → ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate ($0.01-0.05/hour for spot instances)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-002-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask ($0.01/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-004-iam-passrole+ecs-registertaskdefinition+ecs-runtask ($0.01/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-005-iam-passrole+ecs-registertaskdefinition+ecs-starttask ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-003-iam-passrole+ecs-registertaskdefinition+ecs-createservice ($0.02/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-001-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice ($0.02/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-006-ecs-executecommand+describetasks ($0.04/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-007-iam-passrole+ecs-starttask+ecs-registercontainerinstance"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-008-iam-passrole+ecs-runtask"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sts-001-sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-012-iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-006-iam-passrole+lambda-createfunction+lambda-addpermission"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-001-iam-passrole+lambda-createfunction+lambda-invokefunction"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-005-cloudformation-createchangeset+executechangeset"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-002-cloudformation-updatestack"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_004_iam_passrole_cloudformation_updatestackset" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-004-iam-passrole+cloudformation-updatestackset"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-001-iam-passrole-cloudformation"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_003_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-003-iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_001_iam_passrole_codebuild_createproject_codebuild_startbuild" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-001-iam-passrole+codebuild-createproject+codebuild-startbuild"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-004-iam-passrole+codebuild-createproject+codebuild-startbuildbatch"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_021_iam_putrolepolicy_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-021-iam-putrolepolicy+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-017-iam-putrolepolicy+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-018-iam-putuserpolicy+iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_003_lambda_updatefunctioncode" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-003-lambda-updatefunctioncode"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-005-lambda-updatefunctioncode+lambda-addpermission"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-004-lambda-updatefunctioncode+lambda-invokefunction"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ssm-002-ssm-sendcommand"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ssm_001_ssm_startsession" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ssm-001-ssm-startsession"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-002-codebuild-startbuild"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-003-codebuild-startbuildbatch"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-003-ec2-instance-connect-sendsshpublickey ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-002 → ec2-modifyinstanceattribute+stopinstances+startinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-001-iam-passrole+glue-createdevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-002-glue-updatedevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-createjob+glue-createtrigger ($0.10/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-createjob+glue-startjobrun ($0.10/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-005-iam-passrole+glue-updatejob+glue-startjobrun ($0.10/month) (Pathfinding.cloud: glue-005)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-006-iam-passrole+glue-updatejob+glue-createtrigger ($0.10/month) (Pathfinding.cloud: glue-006)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_007_iam_passrole_glue_createsession_glue_runstatement" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-007-iam-passrole+glue-createsession+glue-runstatement ($1/mo) (Pathfinding.cloud: glue-007)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment" {
  description = "Enable: single-account → privesc-one-hop → to-admin → mwaa-001-iam-passrole+airflow-createenvironment (Infrastructure: ~$37/mo NAT Gateway; DEMO creates MWAA ~$350/mo - cleanup immediately!) (Pathfinding.cloud: mwaa-001)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment" {
  description = "Enable: single-account → privesc-one-hop → to-admin → mwaa-002-airflow-updateenvironment (UpdateEnvironment privilege escalation)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-ADMIN SCENARIOS NON-FREE
##############################################################################

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-001 → iam-passrole+sagemaker-createnotebookinstance ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-003 → iam-passrole+sagemaker-createprocessingjob ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-002-iam-passrole+sagemaker-createtrainingjob ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-004-sagemaker-createpresignednotebookinstanceurl ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-005-sagemaker-updatenotebook-lifecycle-config ($5/month)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-BUCKET SCENARIOS
##############################################################################

variable "enable_single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → glue-001 → iam-passrole+glue-createdevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-002-iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-004-iam-createloginprofile"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-003-iam-deleteaccesskey+createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-012-iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → sts-001-sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-006-iam-updateloginprofile"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-BUCKET SCENARIOS NON-FREE
##############################################################################

variable "enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ec2-003-ec2-instance-connect-sendsshpublickey ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → glue-002-glue-updatedevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_ssm_002_ssm_sendcommand" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ssm-002-ssm-sendcommand ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_ssm_001_ssm_startsession" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ssm-001-ssm-startsession ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT MULTI-HOP TO-ADMIN SCENARIOS
##############################################################################

variable "enable_single_account_privesc_multi_hop_to_admin_putrolepolicy_on_other" {
  description = "Enable: single-account → privesc-multi-hop → to-admin → putrolepolicy-on-other"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_multi_hop_to_admin_lambda_004_to_iam_002" {
  description = "Enable: single-account → privesc-multi-hop → to-admin → lambda-004-to-iam-002 (Lambda UpdateFunctionCode to CreateAccessKey chain)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined" {
  description = "Enable: single-account → privesc-multi-hop → to-admin → multiple-paths-combined"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_multi_hop_to_admin_sts_001_to_ecs_002_to_admin" {
  description = "Enable: single-account → privesc-multi-hop → to-admin → sts-001-to-ecs-002-to-admin"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT MULTI-HOP TO-BUCKET SCENARIOS
##############################################################################

variable "enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3" {
  description = "Enable: single-account → privesc-multi-hop → to-bucket → role-chain-to-s3"
  type        = bool
  default     = false
}

##############################################################################
# TOOL TESTING SCENARIOS
##############################################################################

variable "enable_tool_testing_exclusive_resource_policy" {
  description = "Enable: tool-testing → exclusive-resource-policy (tests detection of exclusive resource policy configurations)"
  type        = bool
  default     = false
}

variable "enable_tool_testing_resource_policy_bypass" {
  description = "Enable: tool-testing → resource-policy-bypass (tests detection of resource policies that bypass IAM)"
  type        = bool
  default     = false
}

variable "enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin" {
  description = "Enable: tool-testing → test-reverse-blast-radius-direct-and-indirect-through-admin"
  type        = bool
  default     = false
}

variable "enable_tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket" {
  description = "Enable: tool-testing → test-reverse-blast-radius-direct-and-indirect-to-bucket"
  type        = bool
  default     = false
}

variable "enable_tool_testing_test_effective_permissions_evaluation" {
  description = "Enable: tool-testing → test-effective-permissions-evaluation"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT CSPM-TOXIC-COMBO SCENARIOS
##############################################################################

variable "enable_single_account_cspm_toxic_combo_public_lambda_with_admin" {
  description = "Enable: single-account → cspm-toxic-combo → public-lambda-with-admin"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT CSPM-MISCONFIG SCENARIOS
##############################################################################

variable "enable_single_account_cspm_misconfig_cspm_ec2_001_instance_with_privileged_role" {
  description = "Enable: single-account → cspm-misconfig → cspm-ec2-001-instance-with-privileged-role"
  type        = bool
  default     = false
}

##############################################################################
# CROSS-ACCOUNT DEV-TO-PROD SCENARIOS
##############################################################################

variable "enable_cross_account_dev_to_prod_one_hop_simple_role_assumption" {
  description = "Enable: cross-account → dev-to-prod → one-hop → simple-role-assumption"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → passrole-lambda-admin"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_multi_hop_both_sides" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → multi-hop-both-sides"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update" {
  description = "Enable: cross-account → dev-to-prod → multi-hop → lambda-invoke-update"
  type        = bool
  default     = false
}

variable "enable_cross_account_dev_to_prod_one_hop_root_trust_role_assumption" {
  description = "Enable: cross-account → dev-to-prod → one-hop → root-trust-role-assumption"
  type        = bool
  default     = false
}

##############################################################################
# CROSS-ACCOUNT OPS-TO-PROD SCENARIOS
##############################################################################

variable "enable_cross_account_ops_to_prod_one_hop_simple_role_assumption" {
  description = "Enable: cross-account → ops-to-prod → one-hop → simple-role-assumption"
  type        = bool
  default     = false
}

##############################################################################
# BUDGET ALERT CONFIGURATION
##############################################################################

variable "enable_budget_alerts" {
  description = "Enable AWS Budget alerts for cost monitoring. First 2 budgets per account are FREE."
  type        = bool
  default     = false
}

variable "budget_alert_email" {
  description = "Email address to receive budget alerts (required if enable_budget_alerts is true)"
  type        = string
  default     = ""
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD (applies to each enabled environment)"
  type        = number
  default     = 50
}

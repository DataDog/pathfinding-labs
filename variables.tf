##############################################################################
# ACCOUNT CONFIGURATION
##############################################################################

variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "dev_account_aws_profile" {
  description = "AWS profile for dev environment"
  default     = "pl-pathfinding-starting-user-dev"
}

variable "operations_account_aws_profile" {
  description = "AWS profile for operations account"
  default     = "pl-pathfinding-starting-user-operations"
}

variable "prod_account_aws_profile" {
  description = "AWS profile for prod account"
  default     = "pl-pathfinding-starting-user-prod"
}

variable "prod_account_id" {
  description = "The account id of the prod account"
  type        = string
  default     = ""
}

variable "operations_account_id" {
  description = "The account id of the operations account"
  type        = string
  default     = ""
}

variable "dev_account_id" {
  description = "The account id of the dev account"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "The github repo for the OIDC-GitHub challenge"
  type        = string
  default     = null
}

##############################################################################
# SINGLE-ACCOUNT SELF-ESCALATION TO-ADMIN SCENARIOS
##############################################################################

variable "enable_single_account_privesc_self_escalation_to_admin_iam_putrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_attachrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-attachrolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_createpolicyversion" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-createpolicyversion"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_putuserpolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-putuserpolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_putgrouppolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-putgrouppolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_addusertogroup" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-addusertogroup"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_attachuserpolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-attachuserpolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-admin → iam-attachgrouppolicy"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT SELF-ESCALATION TO-BUCKET SCENARIOS
##############################################################################

variable "enable_single_account_privesc_self_escalation_to_bucket_iam_putrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-bucket → iam-putrolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_self_escalation_to_bucket_iam_attachrolepolicy" {
  description = "Enable: single-account → privesc-self-escalation → to-bucket → iam-attachrolepolicy"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-ADMIN SCENARIOS
##############################################################################

variable "enable_single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-attachrolepolicy+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_attachrolepolicy_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-attachrolepolicy+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_attachuserpolicy_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-attachuserpolicy+iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_apprunner_updateservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → apprunner-updateservice"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_createloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-createloginprofile"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_deleteaccesskey_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-deleteaccesskey+createaccesskey (Pathfinding.cloud: iam-003)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_createpolicyversion_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-createpolicyversion+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_createpolicyversion_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-createpolicyversion+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_updateloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-updateloginprofile"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_apprunner_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+apprunner-createservice"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_bedrockagentcore_codeinterpreter" {
  description = "Enable: single-account → privesc → one-hop → to-admin → iam-passrole+bedrockagentcore-codeinterpreter (Pathfinding.cloud: bedrock-001)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_bedrockagentcore_startsession_invoke" {
  description = "Enable: single-account → privesc → one-hop → to-admin → bedrockagentcore-startsession+invoke (Pathfinding.cloud: bedrock-002)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ec2_runinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ec2-runinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ec2_requestspotinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ec2-requestspotinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate ($0.01-0.05/hour for spot instances)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask ($0.01/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ecs_registertaskdefinition_ecs_runtask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ecs-registertaskdefinition+ecs-runtask ($0.01/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ecs_registertaskdefinition_ecs_starttask" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ecs-registertaskdefinition+ecs-starttask ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ecs_registertaskdefinition_ecs_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ecs-registertaskdefinition+ecs-createservice ($0.02/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice ($0.02/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ecs_executecommand" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ecs-executecommand ($0.04/hour)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_addpermission" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+lambda-createfunction+lambda-addpermission"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_lambda_invokefunction" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+lambda-createfunction+lambda-invokefunction"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_createchangeset_executechangeset" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-createchangeset+executechangeset"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_cloudformation_updatestack" {
  description = "Enable: single-account → privesc-one-hop → to-admin → cloudformation-updatestack"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation_updatestackset" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole-cloudformation-updatestackset"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole-cloudformation"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_cloudformation_createstackset_cloudformation_createstackinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+cloudformation-createstackset+cloudformation-createstackinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuild" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+codebuild-createproject+codebuild-startbuild"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_codebuild_createproject_codebuild_startbuildbatch" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+codebuild-createproject+codebuild-startbuildbatch"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_putrolepolicy_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-putrolepolicy+iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_putrolepolicy_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-putrolepolicy+sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_putuserpolicy_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-putuserpolicy+iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-updatefunctioncode"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode_lambda_addpermission" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-updatefunctioncode+lambda-addpermission"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode_lambda_invokefunction" {
  description = "Enable: single-account → privesc-one-hop → to-admin → lambda-updatefunctioncode+lambda-invokefunction"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ssm_sendcommand" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ssm-sendcommand"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ssm_startsession" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ssm-startsession"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_startbuild" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-startbuild"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_codebuild_startbuildbatch" {
  description = "Enable: single-account → privesc-one-hop → to-admin → codebuild-startbuildbatch"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_instance_connect_sendsshpublickey" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-instance-connect-sendsshpublickey ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_ec2_modifyinstanceattribute_stopinstances_startinstances" {
  description = "Enable: single-account → privesc-one-hop → to-admin → ec2-modifyinstanceattribute+stopinstances+startinstances"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createdevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-createdevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_glue_updatedevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-admin → glue-updatedevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_createtrigger" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-createjob+glue-createtrigger ($0.10/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_createjob_glue_startjobrun" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-createjob+glue-startjobrun ($0.10/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-updatejob+glue-startjobrun ($0.10/month) (Pathfinding.cloud: glue-005)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+glue-updatejob+glue-createtrigger ($0.10/month) (Pathfinding.cloud: glue-006)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-ADMIN SCENARIOS NON-FREE
##############################################################################

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_sagemaker_createnotebookinstance" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+sagemaker-createnotebookinstance ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_sagemaker_createprocessingjob" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+sagemaker-createprocessingjob ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_iam_passrole_sagemaker_createtrainingjob" {
  description = "Enable: single-account → privesc-one-hop → to-admin → iam-passrole+sagemaker-createtrainingjob ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_createpresignednotebookinstanceurl" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-createpresignednotebookinstanceurl ($5/month)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_admin_sagemaker_updatenotebook_lifecycle_config" {
  description = "Enable: single-account → privesc-one-hop → to-admin → sagemaker-updatenotebook-lifecycle-config ($5/month)"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-BUCKET SCENARIOS
##############################################################################

variable "enable_single_account_privesc_one_hop_to_bucket_iam_passrole_glue_createdevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-passrole+glue-createdevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_createloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-createloginprofile"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_deleteaccesskey_createaccesskey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-deleteaccesskey+createaccesskey"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_updateassumerolepolicy" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-updateassumerolepolicy"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_sts_assumerole" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → sts-assumerole"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_iam_updateloginprofile" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → iam-updateloginprofile"
  type        = bool
  default     = false
}

##############################################################################
# SINGLE-ACCOUNT ONE-HOP TO-BUCKET SCENARIOS NON-FREE
##############################################################################

variable "enable_single_account_privesc_one_hop_to_bucket_ec2_instance_connect_sendsshpublickey" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ec2-instance-connect-sendsshpublickey ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_glue_updatedevendpoint" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → glue-updatedevendpoint ($2.20/hour for Glue dev endpoint)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_ssm_sendcommand" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ssm-sendcommand ($5/month for EC2 instance)"
  type        = bool
  default     = false
}

variable "enable_single_account_privesc_one_hop_to_bucket_ssm_startsession" {
  description = "Enable: single-account → privesc-one-hop → to-bucket → ssm-startsession ($5/month for EC2 instance)"
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

variable "enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined" {
  description = "Enable: single-account → privesc-multi-hop → to-admin → multiple-paths-combined"
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
# SINGLE-ACCOUNT TOXIC-COMBO SCENARIOS
##############################################################################

variable "enable_single_account_toxic_combo_public_lambda_with_admin" {
  description = "Enable: single-account → toxic-combo → public-lambda-with-admin"
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

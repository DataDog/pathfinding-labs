# =============================================================================
# STARTING USER OUTPUTS
# =============================================================================

output "starting_user_name" {
  description = "Name of the starting user"
  value       = aws_iam_user.starting_user.name
}

output "starting_user_arn" {
  description = "ARN of the starting user"
  value       = aws_iam_user.starting_user.arn
}

output "starting_user_access_key_id" {
  description = "Access key ID for starting user"
  value       = aws_iam_access_key.starting_user.id
  sensitive   = true
}

output "starting_user_secret_access_key" {
  description = "Secret access key for starting user"
  value       = aws_iam_access_key.starting_user.secret
  sensitive   = true
}

# =============================================================================
# ISADMIN USER OUTPUTS (9 users)
# =============================================================================

# 1. isAdmin-awsmanaged
output "user_isadmin_awsmanaged_name" {
  description = "Name of isAdmin user with AWS managed policy"
  value       = aws_iam_user.isadmin_awsmanaged.name
}

output "user_isadmin_awsmanaged_arn" {
  description = "ARN of isAdmin user with AWS managed policy"
  value       = aws_iam_user.isadmin_awsmanaged.arn
}

output "user_isadmin_awsmanaged_access_key_id" {
  description = "Access key ID for isAdmin-awsmanaged user"
  value       = aws_iam_access_key.isadmin_awsmanaged.id
  sensitive   = true
}

output "user_isadmin_awsmanaged_secret_access_key" {
  description = "Secret access key for isAdmin-awsmanaged user"
  value       = aws_iam_access_key.isadmin_awsmanaged.secret
  sensitive   = true
}

# 2. isAdmin-customermanaged
output "user_isadmin_customermanaged_name" {
  description = "Name of isAdmin user with customer managed policy"
  value       = aws_iam_user.isadmin_customermanaged.name
}

output "user_isadmin_customermanaged_arn" {
  description = "ARN of isAdmin user with customer managed policy"
  value       = aws_iam_user.isadmin_customermanaged.arn
}

output "user_isadmin_customermanaged_access_key_id" {
  description = "Access key ID for isAdmin-customermanaged user"
  value       = aws_iam_access_key.isadmin_customermanaged.id
  sensitive   = true
}

output "user_isadmin_customermanaged_secret_access_key" {
  description = "Secret access key for isAdmin-customermanaged user"
  value       = aws_iam_access_key.isadmin_customermanaged.secret
  sensitive   = true
}

# 3. isAdmin-inline
output "user_isadmin_inline_name" {
  description = "Name of isAdmin user with inline policy"
  value       = aws_iam_user.isadmin_inline.name
}

output "user_isadmin_inline_arn" {
  description = "ARN of isAdmin user with inline policy"
  value       = aws_iam_user.isadmin_inline.arn
}

output "user_isadmin_inline_access_key_id" {
  description = "Access key ID for isAdmin-inline user"
  value       = aws_iam_access_key.isadmin_inline.id
  sensitive   = true
}

output "user_isadmin_inline_secret_access_key" {
  description = "Secret access key for isAdmin-inline user"
  value       = aws_iam_access_key.isadmin_inline.secret
  sensitive   = true
}

# 4. isAdmin-via-group-awsmanaged
output "user_isadmin_via_group_awsmanaged_name" {
  description = "Name of isAdmin user via group with AWS managed policy"
  value       = aws_iam_user.isadmin_via_group_awsmanaged.name
}

output "user_isadmin_via_group_awsmanaged_arn" {
  description = "ARN of isAdmin user via group with AWS managed policy"
  value       = aws_iam_user.isadmin_via_group_awsmanaged.arn
}

output "user_isadmin_via_group_awsmanaged_access_key_id" {
  description = "Access key ID for isAdmin-via-group-awsmanaged user"
  value       = aws_iam_access_key.isadmin_via_group_awsmanaged.id
  sensitive   = true
}

output "user_isadmin_via_group_awsmanaged_secret_access_key" {
  description = "Secret access key for isAdmin-via-group-awsmanaged user"
  value       = aws_iam_access_key.isadmin_via_group_awsmanaged.secret
  sensitive   = true
}

# 5. isAdmin-via-group-customermanaged
output "user_isadmin_via_group_customermanaged_name" {
  description = "Name of isAdmin user via group with customer managed policy"
  value       = aws_iam_user.isadmin_via_group_customermanaged.name
}

output "user_isadmin_via_group_customermanaged_arn" {
  description = "ARN of isAdmin user via group with customer managed policy"
  value       = aws_iam_user.isadmin_via_group_customermanaged.arn
}

output "user_isadmin_via_group_customermanaged_access_key_id" {
  description = "Access key ID for isAdmin-via-group-customermanaged user"
  value       = aws_iam_access_key.isadmin_via_group_customermanaged.id
  sensitive   = true
}

output "user_isadmin_via_group_customermanaged_secret_access_key" {
  description = "Secret access key for isAdmin-via-group-customermanaged user"
  value       = aws_iam_access_key.isadmin_via_group_customermanaged.secret
  sensitive   = true
}

# 6. isAdmin-via-group-inline
output "user_isadmin_via_group_inline_name" {
  description = "Name of isAdmin user via group with inline policy"
  value       = aws_iam_user.isadmin_via_group_inline.name
}

output "user_isadmin_via_group_inline_arn" {
  description = "ARN of isAdmin user via group with inline policy"
  value       = aws_iam_user.isadmin_via_group_inline.arn
}

output "user_isadmin_via_group_inline_access_key_id" {
  description = "Access key ID for isAdmin-via-group-inline user"
  value       = aws_iam_access_key.isadmin_via_group_inline.id
  sensitive   = true
}

output "user_isadmin_via_group_inline_secret_access_key" {
  description = "Secret access key for isAdmin-via-group-inline user"
  value       = aws_iam_access_key.isadmin_via_group_inline.secret
  sensitive   = true
}

# 7. isAdmin-split-iam-and-notiam
output "user_isadmin_split_iam_and_notiam_name" {
  description = "Name of isAdmin user with split IAM/NotIAM policies"
  value       = aws_iam_user.isadmin_split_iam_and_notiam.name
}

output "user_isadmin_split_iam_and_notiam_arn" {
  description = "ARN of isAdmin user with split IAM/NotIAM policies"
  value       = aws_iam_user.isadmin_split_iam_and_notiam.arn
}

output "user_isadmin_split_iam_and_notiam_access_key_id" {
  description = "Access key ID for isAdmin-split-iam-and-notiam user"
  value       = aws_iam_access_key.isadmin_split_iam_and_notiam.id
  sensitive   = true
}

output "user_isadmin_split_iam_and_notiam_secret_access_key" {
  description = "Secret access key for isAdmin-split-iam-and-notiam user"
  value       = aws_iam_access_key.isadmin_split_iam_and_notiam.secret
  sensitive   = true
}

# 8. isAdmin-split-s3-and-nots3
output "user_isadmin_split_s3_and_nots3_name" {
  description = "Name of isAdmin user with split S3/NotS3 policies"
  value       = aws_iam_user.isadmin_split_s3_and_nots3.name
}

output "user_isadmin_split_s3_and_nots3_arn" {
  description = "ARN of isAdmin user with split S3/NotS3 policies"
  value       = aws_iam_user.isadmin_split_s3_and_nots3.arn
}

output "user_isadmin_split_s3_and_nots3_access_key_id" {
  description = "Access key ID for isAdmin-split-s3-and-nots3 user"
  value       = aws_iam_access_key.isadmin_split_s3_and_nots3.id
  sensitive   = true
}

output "user_isadmin_split_s3_and_nots3_secret_access_key" {
  description = "Secret access key for isAdmin-split-s3-and-nots3 user"
  value       = aws_iam_access_key.isadmin_split_s3_and_nots3.secret
  sensitive   = true
}

# 9. isAdmin-many-services-combined
output "user_isadmin_many_services_combined_name" {
  description = "Name of isAdmin user with many services combined"
  value       = aws_iam_user.isadmin_many_services_combined.name
}

output "user_isadmin_many_services_combined_arn" {
  description = "ARN of isAdmin user with many services combined"
  value       = aws_iam_user.isadmin_many_services_combined.arn
}

output "user_isadmin_many_services_combined_access_key_id" {
  description = "Access key ID for isAdmin-many-services-combined user"
  value       = aws_iam_access_key.isadmin_many_services_combined.id
  sensitive   = true
}

output "user_isadmin_many_services_combined_secret_access_key" {
  description = "Secret access key for isAdmin-many-services-combined user"
  value       = aws_iam_access_key.isadmin_many_services_combined.secret
  sensitive   = true
}

# =============================================================================
# NOTADMIN USER OUTPUTS (12 users)
# =============================================================================

# 10. notAdmin-adminpolicy-plus-denyall
output "user_notadmin_adminpolicy_plus_denyall_name" {
  description = "Name of notAdmin user with admin policy + deny all"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denyall.name
}

output "user_notadmin_adminpolicy_plus_denyall_arn" {
  description = "ARN of notAdmin user with admin policy + deny all"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denyall.arn
}

output "user_notadmin_adminpolicy_plus_denyall_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-denyall user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denyall.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_denyall_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-denyall user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denyall.secret
  sensitive   = true
}

# 11. notAdmin-adminpolicy-plus-denynotaction
output "user_notadmin_adminpolicy_plus_denynotaction_name" {
  description = "Name of notAdmin user with admin policy + deny NotAction"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction.name
}

output "user_notadmin_adminpolicy_plus_denynotaction_arn" {
  description = "ARN of notAdmin user with admin policy + deny NotAction"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction.arn
}

output "user_notadmin_adminpolicy_plus_denynotaction_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-denynotaction user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denynotaction.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_denynotaction_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-denynotaction user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denynotaction.secret
  sensitive   = true
}

# 12. notAdmin-adminpolicy-plus-denynotaction-ec2only
output "user_notadmin_adminpolicy_plus_denynotaction_ec2only_name" {
  description = "Name of notAdmin user with admin policy + deny NotAction ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction_ec2only.name
}

output "user_notadmin_adminpolicy_plus_denynotaction_ec2only_arn" {
  description = "ARN of notAdmin user with admin policy + deny NotAction ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_denynotaction_ec2only.arn
}

output "user_notadmin_adminpolicy_plus_denynotaction_ec2only_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-denynotaction-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denynotaction_ec2only.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_denynotaction_ec2only_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-denynotaction-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_denynotaction_ec2only.secret
  sensitive   = true
}

# 13. notAdmin-adminpolicy-plus-deny-split-iam-notiam
output "user_notadmin_adminpolicy_plus_deny_split_iam_notiam_name" {
  description = "Name of notAdmin user with admin policy + deny split iam/notiam"
  value       = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.name
}

output "user_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn" {
  description = "ARN of notAdmin user with admin policy + deny split iam/notiam"
  value       = aws_iam_user.notadmin_adminpolicy_plus_deny_split_iam_notiam.arn
}

output "user_notadmin_adminpolicy_plus_deny_split_iam_notiam_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-deny-split-iam-notiam user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_deny_split_iam_notiam.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_deny_split_iam_notiam_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-deny-split-iam-notiam user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_deny_split_iam_notiam.secret
  sensitive   = true
}

# 14. notAdmin-adminpolicy-plus-deny-incremental
output "user_notadmin_adminpolicy_plus_deny_incremental_name" {
  description = "Name of notAdmin user with admin policy + deny incremental"
  value       = aws_iam_user.notadmin_adminpolicy_plus_deny_incremental.name
}

output "user_notadmin_adminpolicy_plus_deny_incremental_arn" {
  description = "ARN of notAdmin user with admin policy + deny incremental"
  value       = aws_iam_user.notadmin_adminpolicy_plus_deny_incremental.arn
}

output "user_notadmin_adminpolicy_plus_deny_incremental_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-deny-incremental user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_deny_incremental.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_deny_incremental_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-deny-incremental user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_deny_incremental.secret
  sensitive   = true
}

# 15. notAdmin-split-allow-plus-denyall
output "user_notadmin_split_allow_plus_denyall_name" {
  description = "Name of notAdmin user with split allow + deny all"
  value       = aws_iam_user.notadmin_split_allow_plus_denyall.name
}

output "user_notadmin_split_allow_plus_denyall_arn" {
  description = "ARN of notAdmin user with split allow + deny all"
  value       = aws_iam_user.notadmin_split_allow_plus_denyall.arn
}

output "user_notadmin_split_allow_plus_denyall_access_key_id" {
  description = "Access key ID for notAdmin-split-allow-plus-denyall user"
  value       = aws_iam_access_key.notadmin_split_allow_plus_denyall.id
  sensitive   = true
}

output "user_notadmin_split_allow_plus_denyall_secret_access_key" {
  description = "Secret access key for notAdmin-split-allow-plus-denyall user"
  value       = aws_iam_access_key.notadmin_split_allow_plus_denyall.secret
  sensitive   = true
}

# 16. notAdmin-adminpolicy-plus-boundary-allows-nothing
output "user_notadmin_adminpolicy_plus_boundary_allows_nothing_name" {
  description = "Name of notAdmin user with admin policy + boundary allows nothing"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_allows_nothing.name
}

output "user_notadmin_adminpolicy_plus_boundary_allows_nothing_arn" {
  description = "ARN of notAdmin user with admin policy + boundary allows nothing"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_allows_nothing.arn
}

output "user_notadmin_adminpolicy_plus_boundary_allows_nothing_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-boundary-allows-nothing user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_allows_nothing.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_boundary_allows_nothing_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-boundary-allows-nothing user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_allows_nothing.secret
  sensitive   = true
}

# 17. notAdmin-adminpolicy-plus-boundary-ec2only
output "user_notadmin_adminpolicy_plus_boundary_ec2only_name" {
  description = "Name of notAdmin user with admin policy + boundary ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_ec2only.name
}

output "user_notadmin_adminpolicy_plus_boundary_ec2only_arn" {
  description = "ARN of notAdmin user with admin policy + boundary ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_ec2only.arn
}

output "user_notadmin_adminpolicy_plus_boundary_ec2only_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-boundary-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_ec2only.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_boundary_ec2only_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-boundary-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_ec2only.secret
  sensitive   = true
}

# 18. notAdmin-adminpolicy-plus-boundary-notaction-ec2only
output "user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name" {
  description = "Name of notAdmin user with admin policy + boundary notaction ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_notaction_ec2only.name
}

output "user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn" {
  description = "ARN of notAdmin user with admin policy + boundary notaction ec2only"
  value       = aws_iam_user.notadmin_adminpolicy_plus_boundary_notaction_ec2only.arn
}

output "user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_access_key_id" {
  description = "Access key ID for notAdmin-adminpolicy-plus-boundary-notaction-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_notaction_ec2only.id
  sensitive   = true
}

output "user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_secret_access_key" {
  description = "Secret access key for notAdmin-adminpolicy-plus-boundary-notaction-ec2only user"
  value       = aws_iam_access_key.notadmin_adminpolicy_plus_boundary_notaction_ec2only.secret
  sensitive   = true
}

# 19. notAdmin-split-allow-boundary-allows-nothing
output "user_notadmin_split_allow_boundary_allows_nothing_name" {
  description = "Name of notAdmin user with split allow + boundary allows nothing"
  value       = aws_iam_user.notadmin_split_allow_boundary_allows_nothing.name
}

output "user_notadmin_split_allow_boundary_allows_nothing_arn" {
  description = "ARN of notAdmin user with split allow + boundary allows nothing"
  value       = aws_iam_user.notadmin_split_allow_boundary_allows_nothing.arn
}

output "user_notadmin_split_allow_boundary_allows_nothing_access_key_id" {
  description = "Access key ID for notAdmin-split-allow-boundary-allows-nothing user"
  value       = aws_iam_access_key.notadmin_split_allow_boundary_allows_nothing.id
  sensitive   = true
}

output "user_notadmin_split_allow_boundary_allows_nothing_secret_access_key" {
  description = "Secret access key for notAdmin-split-allow-boundary-allows-nothing user"
  value       = aws_iam_access_key.notadmin_split_allow_boundary_allows_nothing.secret
  sensitive   = true
}

# 20. notAdmin-split-allow-boundary-ec2only
output "user_notadmin_split_allow_boundary_ec2only_name" {
  description = "Name of notAdmin user with split allow + boundary ec2only"
  value       = aws_iam_user.notadmin_split_allow_boundary_ec2only.name
}

output "user_notadmin_split_allow_boundary_ec2only_arn" {
  description = "ARN of notAdmin user with split allow + boundary ec2only"
  value       = aws_iam_user.notadmin_split_allow_boundary_ec2only.arn
}

output "user_notadmin_split_allow_boundary_ec2only_access_key_id" {
  description = "Access key ID for notAdmin-split-allow-boundary-ec2only user"
  value       = aws_iam_access_key.notadmin_split_allow_boundary_ec2only.id
  sensitive   = true
}

output "user_notadmin_split_allow_boundary_ec2only_secret_access_key" {
  description = "Secret access key for notAdmin-split-allow-boundary-ec2only user"
  value       = aws_iam_access_key.notadmin_split_allow_boundary_ec2only.secret
  sensitive   = true
}

# 21. notAdmin-split-boundary-mismatch
output "user_notadmin_split_boundary_mismatch_name" {
  description = "Name of notAdmin user with split boundary mismatch"
  value       = aws_iam_user.notadmin_split_boundary_mismatch.name
}

output "user_notadmin_split_boundary_mismatch_arn" {
  description = "ARN of notAdmin user with split boundary mismatch"
  value       = aws_iam_user.notadmin_split_boundary_mismatch.arn
}

output "user_notadmin_split_boundary_mismatch_access_key_id" {
  description = "Access key ID for notAdmin-split-boundary-mismatch user"
  value       = aws_iam_access_key.notadmin_split_boundary_mismatch.id
  sensitive   = true
}

output "user_notadmin_split_boundary_mismatch_secret_access_key" {
  description = "Secret access key for notAdmin-split-boundary-mismatch user"
  value       = aws_iam_access_key.notadmin_split_boundary_mismatch.secret
  sensitive   = true
}

# =============================================================================
# ISADMIN ROLE OUTPUTS (6 roles)
# =============================================================================

# 22. isAdmin-awsmanaged
output "role_isadmin_awsmanaged_name" {
  description = "Name of isAdmin role with AWS managed policy"
  value       = aws_iam_role.isadmin_awsmanaged.name
}

output "role_isadmin_awsmanaged_arn" {
  description = "ARN of isAdmin role with AWS managed policy"
  value       = aws_iam_role.isadmin_awsmanaged.arn
}

# 23. isAdmin-customermanaged
output "role_isadmin_customermanaged_name" {
  description = "Name of isAdmin role with customer managed policy"
  value       = aws_iam_role.isadmin_customermanaged.name
}

output "role_isadmin_customermanaged_arn" {
  description = "ARN of isAdmin role with customer managed policy"
  value       = aws_iam_role.isadmin_customermanaged.arn
}

# 24. isAdmin-inline
output "role_isadmin_inline_name" {
  description = "Name of isAdmin role with inline policy"
  value       = aws_iam_role.isadmin_inline.name
}

output "role_isadmin_inline_arn" {
  description = "ARN of isAdmin role with inline policy"
  value       = aws_iam_role.isadmin_inline.arn
}

# 25. isAdmin-split-iam-and-notiam
output "role_isadmin_split_iam_and_notiam_name" {
  description = "Name of isAdmin role with split IAM/NotIAM policies"
  value       = aws_iam_role.isadmin_split_iam_and_notiam.name
}

output "role_isadmin_split_iam_and_notiam_arn" {
  description = "ARN of isAdmin role with split IAM/NotIAM policies"
  value       = aws_iam_role.isadmin_split_iam_and_notiam.arn
}

# 26. isAdmin-split-s3-and-nots3
output "role_isadmin_split_s3_and_nots3_name" {
  description = "Name of isAdmin role with split S3/NotS3 policies"
  value       = aws_iam_role.isadmin_split_s3_and_nots3.name
}

output "role_isadmin_split_s3_and_nots3_arn" {
  description = "ARN of isAdmin role with split S3/NotS3 policies"
  value       = aws_iam_role.isadmin_split_s3_and_nots3.arn
}

# 27. isAdmin-many-services-combined
output "role_isadmin_many_services_combined_name" {
  description = "Name of isAdmin role with many services combined"
  value       = aws_iam_role.isadmin_many_services_combined.name
}

output "role_isadmin_many_services_combined_arn" {
  description = "ARN of isAdmin role with many services combined"
  value       = aws_iam_role.isadmin_many_services_combined.arn
}

# =============================================================================
# NOTADMIN ROLE OUTPUTS (12 roles)
# =============================================================================

# 28. notAdmin-adminpolicy-plus-denyall
output "role_notadmin_adminpolicy_plus_denyall_name" {
  description = "Name of notAdmin role with admin policy + deny all"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denyall.name
}

output "role_notadmin_adminpolicy_plus_denyall_arn" {
  description = "ARN of notAdmin role with admin policy + deny all"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denyall.arn
}

# 29. notAdmin-adminpolicy-plus-denynotaction
output "role_notadmin_adminpolicy_plus_denynotaction_name" {
  description = "Name of notAdmin role with admin policy + deny NotAction"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction.name
}

output "role_notadmin_adminpolicy_plus_denynotaction_arn" {
  description = "ARN of notAdmin role with admin policy + deny NotAction"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction.arn
}

# 30. notAdmin-adminpolicy-plus-denynotaction-ec2only
output "role_notadmin_adminpolicy_plus_denynotaction_ec2only_name" {
  description = "Name of notAdmin role with admin policy + deny NotAction ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction_ec2only.name
}

output "role_notadmin_adminpolicy_plus_denynotaction_ec2only_arn" {
  description = "ARN of notAdmin role with admin policy + deny NotAction ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_denynotaction_ec2only.arn
}

# 31. notAdmin-adminpolicy-plus-deny-split-iam-notiam
output "role_notadmin_adminpolicy_plus_deny_split_iam_notiam_name" {
  description = "Name of notAdmin role with admin policy + deny split iam/notiam"
  value       = aws_iam_role.notadmin_adminpolicy_plus_deny_split_iam_notiam.name
}

output "role_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn" {
  description = "ARN of notAdmin role with admin policy + deny split iam/notiam"
  value       = aws_iam_role.notadmin_adminpolicy_plus_deny_split_iam_notiam.arn
}

# 32. notAdmin-adminpolicy-plus-deny-incremental
output "role_notadmin_adminpolicy_plus_deny_incremental_name" {
  description = "Name of notAdmin role with admin policy + deny incremental"
  value       = aws_iam_role.notadmin_adminpolicy_plus_deny_incremental.name
}

output "role_notadmin_adminpolicy_plus_deny_incremental_arn" {
  description = "ARN of notAdmin role with admin policy + deny incremental"
  value       = aws_iam_role.notadmin_adminpolicy_plus_deny_incremental.arn
}

# 33. notAdmin-split-allow-plus-denyall
output "role_notadmin_split_allow_plus_denyall_name" {
  description = "Name of notAdmin role with split allow + deny all"
  value       = aws_iam_role.notadmin_split_allow_plus_denyall.name
}

output "role_notadmin_split_allow_plus_denyall_arn" {
  description = "ARN of notAdmin role with split allow + deny all"
  value       = aws_iam_role.notadmin_split_allow_plus_denyall.arn
}

# 34. notAdmin-adminpolicy-plus-boundary-allows-nothing
output "role_notadmin_adminpolicy_plus_boundary_allows_nothing_name" {
  description = "Name of notAdmin role with admin policy + boundary allows nothing"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_allows_nothing.name
}

output "role_notadmin_adminpolicy_plus_boundary_allows_nothing_arn" {
  description = "ARN of notAdmin role with admin policy + boundary allows nothing"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_allows_nothing.arn
}

# 35. notAdmin-adminpolicy-plus-boundary-ec2only
output "role_notadmin_adminpolicy_plus_boundary_ec2only_name" {
  description = "Name of notAdmin role with admin policy + boundary ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_ec2only.name
}

output "role_notadmin_adminpolicy_plus_boundary_ec2only_arn" {
  description = "ARN of notAdmin role with admin policy + boundary ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_ec2only.arn
}

# 36. notAdmin-adminpolicy-plus-boundary-notaction-ec2only
output "role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_name" {
  description = "Name of notAdmin role with admin policy + boundary notaction ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_notaction_ec2only.name
}

output "role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn" {
  description = "ARN of notAdmin role with admin policy + boundary notaction ec2only"
  value       = aws_iam_role.notadmin_adminpolicy_plus_boundary_notaction_ec2only.arn
}

# 37. notAdmin-split-allow-boundary-allows-nothing
output "role_notadmin_split_allow_boundary_allows_nothing_name" {
  description = "Name of notAdmin role with split allow + boundary allows nothing"
  value       = aws_iam_role.notadmin_split_allow_boundary_allows_nothing.name
}

output "role_notadmin_split_allow_boundary_allows_nothing_arn" {
  description = "ARN of notAdmin role with split allow + boundary allows nothing"
  value       = aws_iam_role.notadmin_split_allow_boundary_allows_nothing.arn
}

# 38. notAdmin-split-allow-boundary-ec2only
output "role_notadmin_split_allow_boundary_ec2only_name" {
  description = "Name of notAdmin role with split allow + boundary ec2only"
  value       = aws_iam_role.notadmin_split_allow_boundary_ec2only.name
}

output "role_notadmin_split_allow_boundary_ec2only_arn" {
  description = "ARN of notAdmin role with split allow + boundary ec2only"
  value       = aws_iam_role.notadmin_split_allow_boundary_ec2only.arn
}

# 39. notAdmin-split-boundary-mismatch
output "role_notadmin_split_boundary_mismatch_name" {
  description = "Name of notAdmin role with split boundary mismatch"
  value       = aws_iam_role.notadmin_split_boundary_mismatch.name
}

output "role_notadmin_split_boundary_mismatch_arn" {
  description = "ARN of notAdmin role with split boundary mismatch"
  value       = aws_iam_role.notadmin_split_boundary_mismatch.arn
}

# =============================================================================
# BUCKET OUTPUTS
# =============================================================================

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.bucket
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target_bucket.arn
}

# =============================================================================
# SCENARIO SUMMARY
# =============================================================================

output "scenario_summary" {
  description = "Summary of the test scenario"
  value = {
    total_principals        = 40
    starting_user           = 1
    isadmin_users           = 9
    isadmin_roles           = 6
    notadmin_deny_users     = 6
    notadmin_deny_roles     = 6
    notadmin_boundary_users = 6
    notadmin_boundary_roles = 6
    admin_definition        = "You have * on * without any IAM denies (ignoring resource denies)"
    purpose                 = "Test CSPM tools' ability to evaluate effective permissions across admin patterns, denies, boundaries, and edge cases"
  }
}

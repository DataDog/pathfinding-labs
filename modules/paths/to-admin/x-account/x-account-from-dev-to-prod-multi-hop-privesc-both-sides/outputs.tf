output "josh_user_name" {
  description = "The name of the Josh user in dev"
  value       = aws_iam_user.josh.name
}

output "josh_user_arn" {
  description = "The ARN of the Josh user in dev"
  value       = aws_iam_user.josh.arn
}

output "helpdesk_role_name" {
  description = "The name of the helpdesk role in dev"
  value       = aws_iam_role.helpdesk.name
}

output "helpdesk_role_arn" {
  description = "The ARN of the helpdesk role in dev"
  value       = aws_iam_role.helpdesk.arn
}

output "jeremy_user_name" {
  description = "The name of the Jeremy user in prod"
  value       = aws_iam_user.jeremy.name
}

output "jeremy_user_arn" {
  description = "The ARN of the Jeremy user in prod"
  value       = aws_iam_user.jeremy.arn
}

output "trustsdev_role_name" {
  description = "The name of the trustsdev role in prod"
  value       = aws_iam_role.trustsdev.name
}

output "trustsdev_role_arn" {
  description = "The ARN of the trustsdev role in prod"
  value       = aws_iam_role.trustsdev.arn
}

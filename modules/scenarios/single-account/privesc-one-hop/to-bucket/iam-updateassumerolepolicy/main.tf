terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-one-hop-updateassumerolepolicy-bucket-${var.resource_suffix}"
}

resource "aws_iam_role" "bucket_access_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-updateassumerolepolicy-bucket-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bucket_access_policy" {
  provider = aws.prod
  name     = "s3-access"
  role     = aws_iam_role.bucket_access_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"]
      Resource = [aws_s3_bucket.target_bucket.arn, "${aws_s3_bucket.target_bucket.arn}/*"]
    }]
  })
}

resource "aws_iam_role" "privesc_role" {
  provider = aws.prod
  name     = "pl-prod-one-hop-updateassumerolepolicy-privesc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.account_id}:user/pl-pathfinder-starting-user-prod" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "privesc_policy" {
  provider = aws.prod
  name     = "update-trust-policy"
  role     = aws_iam_role.privesc_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:UpdateAssumeRolePolicy"]
      Resource = aws_iam_role.bucket_access_role.arn
    }]
  })
}

resource "aws_s3_object" "sensitive_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "🎉 SUCCESS! iam:UpdateAssumeRolePolicy to bucket\nFlag: PATHFINDER-UPDATEASSUMEROLEPOLICY-TO-BUCKET-2024"
  etag     = md5("🎉 SUCCESS! iam:UpdateAssumeRolePolicy to bucket\nFlag: PATHFINDER-UPDATEASSUMEROLEPOLICY-TO-BUCKET-2024")
}


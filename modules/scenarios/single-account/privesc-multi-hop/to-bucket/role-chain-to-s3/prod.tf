terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-rcs-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-rcs-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "role-chain-to-s3"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Minimal policy for the starting user (just enough to assume the initial role)
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-rcs-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.prod_account_id}:role/pl-prod-initial-role"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 Bucket - Destination for the role chain
resource "aws_s3_bucket" "prod_role_chain_destination" {
  provider = aws.prod
  bucket   = "pl-prod-role-chain-destination-${var.prod_account_id}-${var.resource_suffix}"
}

# Flag file to demonstrate successful access
resource "aws_s3_object" "flag_file" {
  provider = aws.prod
  bucket   = aws_s3_bucket.prod_role_chain_destination.id
  key      = "flag.txt"
  content  = "🎉 CONGRATULATIONS! You have successfully exploited the 3-hop role assumption chain!\n\nThis file demonstrates that an attacker can gain access to sensitive S3 data by exploiting trust relationships between IAM roles.\n\nAttack Path:\n1. Initial Role → Intermediate Role → S3 Access Role → S3 Bucket\n2. IAM User → Intermediate Role → S3 Access Role → S3 Bucket\n\nThis is a common privilege escalation technique in AWS environments.\n\nFlag: PATHFINDER-ROLE-CHAIN-EXPLOIT-2024"
  etag     = md5("🎉 CONGRATULATIONS! You have successfully exploited the 3-hop role assumption chain!\n\nThis file demonstrates that an attacker can gain access to sensitive S3 data by exploiting trust relationships between IAM roles.\n\nAttack Path:\n1. Initial Role → Intermediate Role → S3 Access Role → S3 Bucket\n2. IAM User → Intermediate Role → S3 Access Role → S3 Bucket\n\nThis is a common privilege escalation technique in AWS environments.\n\nFlag: PATHFINDER-ROLE-CHAIN-EXPLOIT-2024")
}

# Role 3: Final role with S3 access (can be assumed by Role 2)
resource "aws_iam_role" "prod_s3_access_role" {
  provider = aws.prod
  name     = "pl-prod-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.prod_intermediate_role.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-s3-access-role"
    Environment = var.environment
    Scenario    = "role-chain-to-s3"
    Purpose     = "s3-access-role"
  }
}

# Policy for Role 3 - Full read/write access to the S3 bucket
resource "aws_iam_policy" "prod_s3_access_policy" {
  provider    = aws.prod
  name        = "pl-prod-s3-access-policy"
  description = "Full read/write access to role chain destination bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy"
        ]
        Resource = [
          aws_s3_bucket.prod_role_chain_destination.arn,
          "${aws_s3_bucket.prod_role_chain_destination.arn}/*"
        ]
      }
    ]
  })
}

# Attach S3 access policy to Role 3
resource "aws_iam_role_policy_attachment" "prod_s3_access_policy" {
  provider   = aws.prod
  role       = aws_iam_role.prod_s3_access_role.name
  policy_arn = aws_iam_policy.prod_s3_access_policy.arn
}

# Role 2: Intermediate role (can be assumed by Role 1 and IAM User)
resource "aws_iam_role" "prod_intermediate_role" {
  provider = aws.prod
  name     = "pl-prod-intermediate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.prod_initial_role.arn
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:user/${aws_iam_user.prod_chain_user.name}"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-intermediate-role"
    Environment = var.environment
    Scenario    = "role-chain-to-s3"
    Purpose     = "intermediate-role"
  }
}

# Policy for Role 2 - Allows assuming the final S3 access role
resource "aws_iam_policy" "prod_intermediate_policy" {
  provider    = aws.prod
  name        = "pl-prod-intermediate-policy"
  description = "Allows assuming the S3 access role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.prod_s3_access_role.arn
      }
    ]
  })
}

# Attach intermediate policy to Role 2
resource "aws_iam_role_policy_attachment" "prod_intermediate_policy" {
  provider   = aws.prod
  role       = aws_iam_role.prod_intermediate_role.name
  policy_arn = aws_iam_policy.prod_intermediate_policy.arn
}

# Role 1: Initial role (can be assumed by the scenario-specific starting user)
resource "aws_iam_role" "prod_initial_role" {
  provider = aws.prod
  name     = "pl-prod-initial-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.starting_user.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-initial-role"
    Environment = var.environment
    Scenario    = "role-chain-to-s3"
    Purpose     = "initial-role"
  }
}

# # Policy for Role 1 - Allows assuming the intermediate role
# resource "aws_iam_policy" "prod_initial_policy" {
#   provider = aws.prod
#   name     = "prod-initial-policy"
#   description = "Allows assuming the intermediate role"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = "sts:AssumeRole"
#         Resource = aws_iam_role.prod_intermediate_role.arn
#       }
#     ]
#   })
# }

# # Attach initial policy to Role 1
# resource "aws_iam_role_policy_attachment" "prod_initial_policy" {
#   provider   = aws.prod
#   role       = aws_iam_role.prod_initial_role.name
#   policy_arn = aws_iam_policy.prod_initial_policy.arn
# }

# IAM User that can assume the intermediate role
resource "aws_iam_user" "prod_chain_user" {
  provider = aws.prod
  name     = "pl-prod-role-chain-user"
}

# # Policy for the IAM user to assume the intermediate role
# resource "aws_iam_user_policy" "prod_chain_user_policy" {
#   provider = aws.prod
#   name     = "prod-role-chain-user-policy"
#   user     = aws_iam_user.prod_chain_user.name

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = "sts:AssumeRole"
#         Resource = aws_iam_role.prod_intermediate_role.arn
#       }
#     ]
#   })
# }

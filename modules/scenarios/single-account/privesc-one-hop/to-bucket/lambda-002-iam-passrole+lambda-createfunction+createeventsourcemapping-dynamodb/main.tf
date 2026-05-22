terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.prod]
    }
  }
}

# PassRole + Lambda CreateFunction + CreateEventSourceMapping (DynamoDB) to-bucket privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction, and
# lambda:CreateEventSourceMapping can access a sensitive S3 bucket by:
# 1. Creating a Lambda function with a role that has S3 and DynamoDB write access
# 2. Linking it to a DynamoDB stream via event source mapping
# 3. Triggering execution by inserting data into the trigger table
# 4. Lambda reads flag.txt from the target S3 bucket and writes it to the exfil DynamoDB table
# 5. Attacker reads the flag from the exfil table via dynamodb:GetItem

# Resource naming convention: pl-prod-lambda-002-to-bucket-{resource-type}
# Path ID: lambda-002 (from pathfinding.cloud)

# =============================================================================
# SCENARIO-SPECIFIC STARTING USER
# =============================================================================

resource "aws_iam_user" "starting_user" {
  force_destroy = true
  provider      = aws.prod
  name          = "pl-prod-lambda-002-to-bucket-starting-user"

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-starting-user"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "starting-user"
  }
}

# Create access keys for the starting user
resource "aws_iam_access_key" "starting_user_key" {
  provider = aws.prod
  user     = aws_iam_user.starting_user.name
}

# Starting user policy with required and helpful permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-002-to-bucket-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RequiredForExploitationPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Sid    = "RequiredForExploitationLambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:CreateEventSourceMapping"
        ]
        Resource = "*"
      },
      {
        Sid    = "HelpfulForReconAndMonitoring"
        Effect = "Allow"
        Action = [
          "dynamodb:ListStreams",
          "dynamodb:DescribeStream",
          "dynamodb:DescribeTable",
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetEventSourceMapping",
          "iam:ListRoles",
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# TARGET ROLE WITH S3 AND DYNAMODB ACCESS
# =============================================================================

# Target role trusted by Lambda — has S3 read access on the bucket and
# DynamoDB write access on the exfil table so the Lambda can exfiltrate the flag.
resource "aws_iam_role" "target_role" {
  force_detach_policies = true
  provider              = aws.prod
  name                  = "pl-prod-lambda-002-to-bucket-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "target-role"
  }
}

# Policy granting the target role S3 read access on the bucket and
# DynamoDB write access on the exfil table.
resource "aws_iam_role_policy" "target_role_policy" {
  provider = aws.prod
  name     = "pl-prod-lambda-002-to-bucket-target-role-policy"
  role     = aws_iam_role.target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.target_bucket.arn,
          "${aws_s3_bucket.target_bucket.arn}/*"
        ]
      },
      {
        Sid    = "DynamoDBExfilWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.exfil_table.arn
      }
    ]
  })
}

# AWSLambdaDynamoDBExecutionRole is required for Lambda to poll the DynamoDB stream
# (grants dynamodb:GetRecords, dynamodb:GetShardIterator, dynamodb:DescribeStream,
# dynamodb:ListStreams, and cloudwatch:PutMetricData / logs:CreateLogGroup etc.)
resource "aws_iam_role_policy_attachment" "target_role_lambda_dynamodb_execution" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

# =============================================================================
# TARGET S3 BUCKET WITH SENSITIVE DATA AND CTF FLAG
# =============================================================================

resource "aws_s3_bucket" "target_bucket" {
  provider = aws.prod
  bucket   = "pl-prod-lambda-002-to-bucket-${var.account_id}-${var.resource_suffix}"

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-target-bucket"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "target-bucket"
  }
}

# Block public access — this is a private bucket
resource "aws_s3_bucket_public_access_block" "target_bucket" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Decoy sensitive file to demonstrate the bucket contains valuable data
resource "aws_s3_object" "sensitive_data" {
  provider = aws.prod
  bucket   = aws_s3_bucket.target_bucket.id
  key      = "sensitive-data.txt"
  content  = "This is sensitive data that should only be accessible to authorized principals."
}

# CTF flag stored as an S3 object in the target bucket.
# The attacker's Lambda (running as target_role) reads this file and writes the
# content to the exfil DynamoDB table. The attacker retrieves it from there via GetItem.
resource "aws_s3_object" "flag" {
  provider     = aws.prod
  bucket       = aws_s3_bucket.target_bucket.id
  key          = "flag.txt"
  content      = var.flag_value
  content_type = "text/plain"

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-flag"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "ctf-flag"
  }
}

# =============================================================================
# DYNAMODB TABLES
# =============================================================================

# Trigger table — DynamoDB streams enabled. The attacker creates an Event Source
# Mapping from this table's stream to their Lambda function, then inserts a record
# to fire the Lambda.
resource "aws_dynamodb_table" "trigger_table" {
  provider     = aws.prod
  name         = "pl-prod-lambda-002-to-bucket-trigger-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-trigger-table"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "lambda-trigger"
  }
}

# Exfil table — NO stream, so the Lambda writing here does not create an infinite
# trigger loop. The attacker reads the flag from this table using dynamodb:GetItem.
resource "aws_dynamodb_table" "exfil_table" {
  provider     = aws.prod
  name         = "pl-prod-lambda-002-to-bucket-exfil-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # stream_enabled intentionally omitted (defaults to false) to prevent
  # infinite Lambda invocation loops when the Lambda writes here.

  tags = {
    Name        = "pl-prod-lambda-002-to-bucket-exfil-table"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "flag-exfil"
  }
}

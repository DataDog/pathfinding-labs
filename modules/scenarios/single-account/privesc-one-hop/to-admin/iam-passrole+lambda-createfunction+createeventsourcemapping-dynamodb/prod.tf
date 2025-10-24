# PassRole + Lambda CreateFunction + CreateEventSourceMapping (DynamoDB) privilege escalation scenario
#
# This scenario demonstrates how a user with iam:PassRole, lambda:CreateFunction, and
# lambda:CreateEventSourceMapping can escalate privileges by:
# 1. Creating a Lambda function with a privileged role
# 2. Linking it to a DynamoDB stream via event source mapping
# 3. Triggering execution by inserting data into the table
# 4. Lambda uses its privileged role to grant admin access

# Resource naming convention: pl-prod-prcfcesmd-to-admin-{resource-type}
# Shorthand: prcfcesmd = PassRole+CreateFunction+CreateEventSourceMapping-DynamoDB

# Scenario-specific starting user
resource "aws_iam_user" "starting_user" {
  provider = aws.prod
  name     = "pl-prod-prcfcesmd-to-admin-starting-user"

  tags = {
    Name        = "pl-prod-prcfcesmd-to-admin-starting-user"
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

# Starting user policy with PassRole, Lambda, and DynamoDB permissions
resource "aws_iam_user_policy" "starting_user_policy" {
  provider = aws.prod
  name     = "pl-prod-prcfcesmd-to-admin-starting-user-policy"
  user     = aws_iam_user.starting_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.target_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:CreateEventSourceMapping",
          "lambda:GetEventSourceMapping",
          "lambda:ListFunctions",
          "lambda:GetFunction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:ListStreams",
          "dynamodb:DescribeStream",
          "dynamodb:DescribeTable",
          "dynamodb:PutItem"
        ]
        Resource = [
          aws_dynamodb_table.trigger_table.arn,
          "${aws_dynamodb_table.trigger_table.arn}/stream/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListRoles"
        ]
        Resource = "*"
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

# Target role with admin access (Lambda will assume this)
resource "aws_iam_role" "target_role" {
  provider = aws.prod
  name     = "pl-prod-prcfcesmd-to-admin-target-role"

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
    Name        = "pl-prod-prcfcesmd-to-admin-target-role"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "admin-target"
  }
}

# Attach AdministratorAccess to the target role
resource "aws_iam_role_policy_attachment" "target_role_admin_access" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attach Lambda DynamoDB execution role for stream polling
resource "aws_iam_role_policy_attachment" "target_role_lambda_dynamodb_execution" {
  provider   = aws.prod
  role       = aws_iam_role.target_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

# DynamoDB table with streams enabled (triggers Lambda execution)
resource "aws_dynamodb_table" "trigger_table" {
  provider     = aws.prod
  name         = "pl-prod-prcfcesmd-to-admin-trigger-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Name        = "pl-prod-prcfcesmd-to-admin-trigger-table"
    Environment = var.environment
    Scenario    = "iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb"
    Purpose     = "lambda-trigger"
  }
}

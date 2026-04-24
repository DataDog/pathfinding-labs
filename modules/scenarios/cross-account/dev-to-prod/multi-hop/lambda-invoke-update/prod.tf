# Lambda execution role with admin permissions (this is what we'll extract)
resource "aws_iam_role" "prod_lambda_execution_role" {
  provider = aws.prod
  name     = "pl-prod-lambda-execution-role"

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
}

# Attach admin policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "prod_lambda_execution_admin" {
  provider   = aws.prod
  role       = aws_iam_role.prod_lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create a simple hello world Lambda function
resource "aws_lambda_function" "prod_hello_world" {
  provider         = aws.prod
  filename         = "${path.module}/lambda/hello_world.zip"
  function_name    = "pl-prod-hello-world-${var.prod_account_id}-${var.resource_suffix}"
  role             = aws_iam_role.prod_lambda_execution_role.arn
  handler          = "hello_world.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.hello_world_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.prod_lambda_execution_admin
  ]
}

# Create the hello world Python code
data "archive_file" "hello_world_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda/hello_world.zip"
  source {
    content  = <<EOF
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Hello from Pathfinding Labs!'
    }
EOF
    filename = "hello_world.py"
  }
}

# Lambda resource policy that trusts the entire dev account
resource "aws_lambda_permission" "allow_dev_account" {
  provider      = aws.prod
  statement_id  = "AllowDevAccount"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prod_hello_world.function_name
  principal     = "arn:aws:iam::${var.dev_account_id}:root"
}

# Additional permission for UpdateFunctionCode
resource "aws_lambda_permission" "allow_dev_account_update" {
  provider      = aws.prod
  statement_id  = "AllowDevAccountUpdate"
  action        = "lambda:UpdateFunctionCode"
  function_name = aws_lambda_function.prod_hello_world.function_name
  principal     = "arn:aws:iam::${var.dev_account_id}:root"
}

resource "aws_ssm_parameter" "flag" {
  provider = aws.prod
  name     = "/pathfinding-labs/flags/lambda-invoke-update-to-admin"
  type     = "String"
  value    = var.flag_value

  tags = {
    Name     = "pl-prod-lambda-invoke-update-to-admin-flag"
    Scenario = "lambda-invoke-update"
    Purpose  = "ctf-flag"
  }
}

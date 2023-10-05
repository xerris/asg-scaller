provider "aws" {
  region = "us-east-1"  # Change to your desired AWS region
}

resource "aws_iam_role" "lambda_role" {
  name = "ASG_Scaller_Lambda_Role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      }
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "ASG_Scaller_Lambda_Policy"
  description = "IAM policy for Lambda function"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:GetItem"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["autoscaling:UpdateAutoScalingGroup", "autoscaling:Describe*","autoscaling:Get*"],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_role.name
}

resource "aws_dynamodb_table" "dynamodb_table" {
  name         = "ASG_Scaller_Storage"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ASGName"

  attribute {
    name = "ASGName"
    type = "S"
  }
}

data "archive_file" "lambda_function_zip" {  
  type        = "zip"  
  source_file = "./asg_scaller.py" 
  output_path = "./asg_scaller.zip"
}

resource "aws_lambda_function" "lambda_function" {
  function_name    = "ASG_Scaller"
  role             = aws_iam_role.lambda_role.arn
  handler          = "asg_scaller.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_function_zip.output_path
  source_code_hash = data.archive_file.lambda_function_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_dynamodb_table.dynamodb_table,
  ]
}

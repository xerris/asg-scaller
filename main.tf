provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  default     = "ASG_Scaller"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  default     = "ASG_Scaller_Storage"
}

variable "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch Events rule"
  default     = "ASG_Scaller_Schedule"
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
  name         = var.dynamodb_table_name
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
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "asg_scaller.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_function_zip.output_path
  source_code_hash = data.archive_file.lambda_function_zip.output_base64sha256
}

 
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name        = var.cloudwatch_event_rule_name
  description = "Schedule rule for ASG Scaller Lambda"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = aws_cloudwatch_event_rule.lambda_schedule.name
  arn  = aws_lambda_function.lambda_function.arn
}


resource "aws_lambda_permission" "allow_cloudwatch_to_call_rw_fallout_retry_step_deletion_lambda" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.lambda_schedule.arn
}

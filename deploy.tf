terraform {
  backend "s3" {
    bucket = "sod-auctions-deployments"
    key    = "terraform/item_updater_trigger"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "app_name" {
  type    = string
  default = "item_updater_trigger"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/bootstrap"
  output_path = "${path.module}/lambda_function.zip"
}

data "local_file" "lambda_zip_contents" {
  filename = data.archive_file.lambda_zip.output_path
}

data "aws_ssm_parameter" "db_connection_string" {
  name = "/db-connection-string"
}

data "aws_ssm_parameter" "blizzard_client_id" {
  name = "/blizzard-client-id"
}

data "aws_ssm_parameter" "blizzard_client_secret" {
  name = "/blizzard-client-secret"
}

data "aws_sqs_queue" "item_ids_queue" {
  name = "item-ids"
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.app_name}_execution_role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
        ],
        "Resource" : [
          "arn:aws:s3:::sod-auctions/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        "Resource": [
          data.aws_sqs_queue.item_ids_queue.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "item_updater_trigger" {
  function_name    = var.app_name
  architectures    = ["arm64"]
  memory_size      = 128
  handler          = "bootstrap"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.local_file.lambda_zip_contents.content_md5
  runtime          = "provided.al2023"
  timeout          = 60

  environment {
    variables = {
      DB_CONNECTION_STRING = data.aws_ssm_parameter.db_connection_string.value
      BLIZZARD_CLIENT_ID = data.aws_ssm_parameter.blizzard_client_id.value
      BLIZZARD_CLIENT_SECRET = data.aws_ssm_parameter.blizzard_client_secret.value
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = data.aws_sqs_queue.item_ids_queue.arn
  function_name = aws_lambda_function.item_updater_trigger.arn
  batch_size = 25
  maximum_batching_window_in_seconds = 10
  scaling_config {
    maximum_concurrency = 2
  }
}

resource "aws_lambda_function_event_invoke_config" "example" {
  function_name                = aws_lambda_function.item_updater_trigger.function_name
  maximum_retry_attempts       = 0
}

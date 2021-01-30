provider "archive" {
  version = "~> 1.1"
}

data "archive_file" "rds_creation_zip" {
  type        = "zip"
  output_path = "./rds_creation.zip"
  source_dir  = "./lambda/rds_creation/"
}

data "archive_file" "rds_setup_zip" {
  type        = "zip"
  output_path = "./rds_setup.zip"
  source_dir  = "./lambda/rds_setup/"
}

locals {
  creation_filename = "./rds_creation.zip"
  setup_filename    = "./rds_setup.zip"
}

resource "aws_db_event_subscription" "creation" {
  name             = "rds-creation"
  sns_topic        = aws_sns_topic.rds.arn
  source_type      = "db-instance"
  event_categories = ["creation"]
}

# 'External' Lambda function that gets the new database SNS notification
# and queries the AWS API to obtain further details about this.
#
# It then sends those details off to another SNS notification, which is
# picked up by the 'internal' Lambda function.
resource "aws_lambda_function" "rds_creation" {
  function_name    = "rds-creation"
  handler          = "index.handler"
  filename         = local.creation_filename
  source_code_hash = base64sha256(local.creation_filename)

  role    = aws_iam_role.rds_external_lambda.arn
  runtime = "nodejs12.x"
  timeout = 10

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.internal.arn
    }
  }
}

# 'Internal' Lambda function which receives database information from
# the external function (via SNS) and then connects to the database
# and evaluates the script against it.
#
# This operates within the VPC, and hence does not have access to the
# internet or AWS APIs.
resource "aws_lambda_function" "rds_setup" {
  function_name    = "rds-setup"
  handler          = "index.handler"
  filename         = local.setup_filename
  source_code_hash = base64sha256(local.setup_filename)

  role        = aws_iam_role.rds_internal_lambda.arn
  runtime     = "nodejs12.x"
  timeout     = 120
  memory_size = 512

  vpc_config {
    subnet_ids         = module.vpc.database_subnets
    security_group_ids = [module.eks.worker_security_group_id]
  }

  environment {
    variables = {
      PGPASSWORD         = random_password.db.result
      BUCKET             = aws_s3_bucket.postgres.id
      REGION             = local.aws_region
      SECRETID           = "testpair"
      QUERY_COMMANDS_KEY = tolist(fileset(path.module, "postgres/*.sql"))[0]
      RDS_CERT_KEY       = tolist(fileset(path.module, "postgres/*.pem"))[0]
    }
  }
}

resource "aws_lambda_permission" "rds_creation" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_creation.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.rds.arn
}

resource "aws_lambda_permission" "rds_setup" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_setup.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.internal.arn
}

resource "aws_sns_topic" "rds" {
  name = "rds-creation"
}

resource "aws_sns_topic" "internal" {
  name = "rds-setup"
}

resource "aws_sns_topic_subscription" "rds" {
  topic_arn = aws_sns_topic.rds.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.rds_creation.arn
}

resource "aws_sns_topic_subscription" "rds_internal" {
  topic_arn = aws_sns_topic.internal.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.rds_setup.arn
}

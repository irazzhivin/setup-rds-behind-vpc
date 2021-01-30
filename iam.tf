data "aws_caller_identity" "current" {}

resource "aws_iam_role" "rds_external_lambda" {
  name = "RDSExternal"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "rds_internal_lambda" {
  name = "RDSInternal"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${data.aws_caller_identity.current.arn}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "rds_internal" {
  name   = "RDSInternalNotifications"
  role   = aws_iam_role.rds_internal_lambda.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ],
    "Resource": "*"
  }]
}
EOF
}

resource "aws_iam_role_policy" "rds_external" {
  name   = "RDSExternalNotifications"
  role   = aws_iam_role.rds_external_lambda.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "rds:DescribeDBInstances"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": ["${aws_sns_topic.rds.arn}",
      "${aws_sns_topic.internal.arn}",
      "${aws_lambda_function.rds_setup.arn}",
      "${aws_lambda_function.rds_creation.arn}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "rds_dump" {
  name   = "access-tosql-dump"
  role   = aws_iam_role.rds_internal_lambda.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": [
              "${aws_s3_bucket.postgres.arn}",
              "${aws_s3_bucket.postgres.arn}/*"
              ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "rds_lambda_vpc" {
  role       = aws_iam_role.rds_internal_lambda.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambdasecrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      "arn:aws:secretsmanager:${local.aws_region}:${data.aws_caller_identity.current.account_id}:secret:testpair*"
    ]
  }

  statement {
    actions = [
      "kms:Decrypt",
    ]

    resources = [
      data.aws_kms_alias.ssm.target_key_arn
    ]
  }
}


resource "aws_iam_policy" "lambdasecrets" {
  name_prefix = "lambda-secrets-"
  path        = "/"
  description = "Lambda access to secrets manager"
  policy      = data.aws_iam_policy_document.lambdasecrets.json
}

resource "aws_iam_role_policy_attachment" "lambdatosecret" {
  role       = aws_iam_role.rds_internal_lambda.id
  policy_arn = aws_iam_policy.lambdasecrets.arn
}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/secretsmanager"
}

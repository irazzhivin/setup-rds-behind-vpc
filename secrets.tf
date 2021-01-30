#DB
locals {
  db_parameters = {
    address   = module.rds.this_db_instance_address
    password  = random_password.db.result
    sourcedb  = module.rds.this_db_instance_name
    dbuser    = module.rds.this_db_instance_username
  }
}

resource "aws_secretsmanager_secret" "db" {
  name       = "rds"
  kms_key_id = data.aws_kms_alias.ssm.target_key_arn
}

resource "aws_secretsmanager_secret_version" "db_version" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode(local.db_parameters)
}

# setup-rds-behind-vpc
# Terraform specification with Lambda to run custom sql queries when rds starts up (Backups, create database users, create databases and etc.)
# Labmda works on nodejs.
# You can configure sql commands by changing code in ./lambda/rds-setup/index.js
# For example in this repo, lambda use variables from Amazon Secrets Manager to create new users and databases in one RDS instance (when rds starts up) which only available from private VPC

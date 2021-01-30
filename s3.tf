resource "aws_s3_bucket" "postgres" {
  bucket = local.bucket-name

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  acl = "private"
}

resource "aws_s3_bucket_object" "stuff" {
  for_each = fileset(path.module, "postgres/**")
  bucket   = aws_s3_bucket.postgres.bucket
  key      = each.value
  source   = "${path.module}/${each.value}"
  etag     = filemd5("${path.module}/${each.value}")
}

resource "aws_s3_bucket_public_access_block" "access" {
  bucket = aws_s3_bucket.postgres.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  bucket-name = "postgres-init-${data.aws_caller_identity.current.account_id}"
}
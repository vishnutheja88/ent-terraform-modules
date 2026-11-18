############################################################
# Wrapper: org-standard S3 bucket on top of terraform-aws-modules/s3-bucket
# Public access blocked, encrypted, TLS-only, owner-enforced, versioned.
############################################################

module "this" {
  source = "../../upstream/terraform-aws-s3-bucket"

  bucket        = var.name
  force_destroy = var.force_destroy

  # Org standards (not exposed to app teams)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  attach_policy                         = true
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  server_side_encryption_configuration = {
    rule = {
      bucket_key_enabled = var.kms_key_arn != null
      apply_server_side_encryption_by_default = {
        sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
        kms_master_key_id = var.kms_key_arn
      }
    }
  }

  versioning = {
    enabled = var.versioning
  }

  lifecycle_rule = var.expire_days == null ? [] : [
    {
      id      = "expire-objects"
      enabled = true
      filter  = {}
      expiration = {
        days = var.expire_days
      }
      noncurrent_version_expiration = {
        noncurrent_days = var.expire_days
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = var.tags
}

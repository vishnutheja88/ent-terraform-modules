############################################################
# Wrapper: IAM Role for a Kubernetes Service Account (IRSA)
# on top of terraform-aws-modules/iam//modules/iam-role-for-service-accounts
# - trust: exactly ONE namespace:serviceaccount via the cluster's OIDC provider
# - permissions: exactly the bucket(s) passed in
############################################################

locals {
  write_actions = ["s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]

  object_arns = [for b in var.bucket_arns : "${b}/*"]
}

module "this" {
  source = "../../upstream/terraform-aws-iam/modules/iam-role-for-service-accounts"

  name                 = var.name
  use_name_prefix      = false
  description          = "IRSA for ${var.namespace}/${var.service_account}"
  permissions_boundary = var.permissions_boundary_arn

  oidc_providers = {
    cluster = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account}"]
    }
  }

  create_policy = true
  policy_name   = "${var.name}-s3"
  permissions = merge(
    {
      bucket = {
        sid       = "Bucket"
        actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
        resources = var.bucket_arns
      }
      objectsread = {
        sid       = "ObjectsRead"
        actions   = ["s3:GetObject", "s3:GetObjectVersion"]
        resources = local.object_arns
      }
    },
    var.read_only ? {} : {
      objectswrite = {
        sid       = "ObjectsWrite"
        actions   = local.write_actions
        resources = local.object_arns
      }
    },
    var.kms_key_arn == null ? {} : {
      kms = {
        sid       = "Kms"
        actions   = var.read_only ? ["kms:Decrypt"] : ["kms:Decrypt", "kms:GenerateDataKey"]
        resources = [var.kms_key_arn]
      }
    }
  )

  tags = var.tags
}

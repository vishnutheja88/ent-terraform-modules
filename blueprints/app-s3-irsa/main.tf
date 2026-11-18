##########################################################################
# Blueprint: app-s3-irsa  (a small Rafay-style "Environment Template")
# One app = one S3 bucket + one IRSA role, plugged into an EXISTING cluster.
# Own values file, own state: deleting an app can never touch the platform.
##########################################################################

data "aws_caller_identity" "current" {}

locals {
  cfg  = yamldecode(file(var.values_file))
  env  = local.cfg.env
  app  = local.cfg.app
  name = "${local.env}-${local.app}"

  # Bucket names are global: add the account id so dev-orders never collides
  bucket_name = "${local.name}-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    {
      Environment = local.env
      App         = local.app
      ManagedBy   = "terraform"
      Blueprint   = "app-s3-irsa"
    },
    try(local.cfg.tags, {})
  )
}

# ---------- Plug into the existing cluster (created by the platform blueprint) ----------
data "aws_eks_cluster" "this" {
  name = local.cfg.cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# ---------- Resources ----------
module "s3" {
  source = "../../modules/s3"

  name          = local.bucket_name
  versioning    = try(local.cfg.s3.versioning, true)
  expire_days   = try(local.cfg.s3.expire_days, null)
  kms_key_arn   = try(local.cfg.s3.kms_key_arn, null)
  force_destroy = try(local.cfg.s3.force_destroy, false)
  tags          = local.tags
}

module "irsa" {
  source = "../../modules/irsa"

  name                     = "${local.name}-s3"
  oidc_provider_arn        = data.aws_iam_openid_connect_provider.eks.arn
  namespace                = local.cfg.irsa.namespace
  service_account          = local.cfg.irsa.service_account
  bucket_arns              = [module.s3.arn]
  read_only                = try(local.cfg.irsa.access, "read-write") == "read-only"
  kms_key_arn              = try(local.cfg.s3.kms_key_arn, null)
  permissions_boundary_arn = try(local.cfg.permissions_boundary_arn, null)
  tags                     = local.tags
}

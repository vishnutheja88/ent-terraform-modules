################################################################################
# The provider talks to the SPOKE account using the profile the buildspec wrote
# after `aws sts assume-role` (ExternalId + session tags).
# The S3 backend keeps using the CodeBuild role in Shared Services, so state
# never leaves the central bucket and spoke roles need no access to it.
################################################################################

provider "aws" {
  region  = local.cfg.region
  profile = var.aws_profile

  # Hard stop if the credentials point at any other account.
  allowed_account_ids = [var.target_account_id]

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  region = local.cfg.region

  # Cross-account deploy: CodeBuild assumes the role named in values.yaml
  dynamic "assume_role" {
    for_each = try(local.cfg.account_role, null) == null ? [] : [local.cfg.account_role]
    content {
      role_arn     = assume_role.value
      session_name = "ent-tf-${local.env}"
    }
  }

  default_tags {
    tags = local.tags
  }
}

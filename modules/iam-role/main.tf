############################################################
# Wrapper: IAM role on top of terraform-aws-modules/iam//modules/iam-role
# The values file says "who can assume it" + "which policies"; we build the trust doc.
############################################################

locals {
  service_trust = length(var.trusted_services) == 0 ? {} : {
    services = {
      actions    = ["sts:AssumeRole"]
      principals = [{ type = "Service", identifiers = var.trusted_services }]
    }
  }

  account_trust = length(var.trusted_role_arns) == 0 ? {} : {
    roles = {
      actions    = ["sts:AssumeRole"]
      principals = [{ type = "AWS", identifiers = var.trusted_role_arns }]
    }
  }
}

module "this" {
  source = "../../upstream/terraform-aws-iam/modules/iam-role"

  name                 = var.name
  use_name_prefix      = false
  description          = var.description
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  trust_policy_permissions = merge(local.service_trust, local.account_trust)
  policies                 = var.policy_arns

  create_instance_profile = var.create_instance_profile

  tags = var.tags
}

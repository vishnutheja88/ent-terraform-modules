################################################################################
# modules/acm-private-cert
# Issues a PRIVATE certificate in the spoke account from the Subordinate CA
# that the Security/PKI account shares through AWS RAM.
#
# - No DNS/email validation: ACM issues private certs immediately.
# - ACM renews automatically before expiry (the CA must stay ACTIVE).
# - The CA ARN is injected by the pipeline (SSM -> TF_VAR), never hardcoded.
################################################################################

data "aws_region" "current" {}

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  certificate_authority_arn = var.certificate_authority_arn
  key_algorithm             = var.key_algorithm

  tags = merge(var.tags, { Name = var.domain_name })

  lifecycle {
    # ALB listeners reference this cert: create the new one before deleting the old.
    create_before_destroy = true

    precondition {
      # ACM can only use a private CA that lives in the same region.
      condition     = split(":", var.certificate_authority_arn)[3] == data.aws_region.current.region
      error_message = "The shared Subordinate CA must be in the same region as this stack."
    }
  }
}

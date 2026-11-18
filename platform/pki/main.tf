################################################################################
# platform/pki  -  run ONCE in the Security/PKI account by the central team.
#
#   Root CA (offline-style, never shared)
#     └── signs ──► Subordinate CA (PathLen0: can only issue end-entity certs)
#                     └── shared to the AWS Organization through AWS RAM
#
# Spoke accounts request certificates from the Subordinate CA with
# aws_acm_certificate.certificate_authority_arn (modules/acm-private-cert).
# The Root CA has NO RAM association: workload accounts can never use it.
################################################################################

terraform {
  required_version = ">= 1.11.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
  }
  backend "s3" {} # partial config, see README
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { ManagedBy = "platform-terraform", Component = "pki" }
  }
}

data "aws_partition" "current" {}

# ---------------------------------------------------------------- Root CA
resource "aws_acmpca_certificate_authority" "root" {
  type       = "ROOT"
  usage_mode = "GENERAL_PURPOSE"

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = var.root_common_name
      organization        = var.organization
      organizational_unit = "Platform PKI"
      country             = var.country
    }
  }

  permanent_deletion_time_in_days = 30

  lifecycle {
    prevent_destroy = true
  }
}

# Self-signed root certificate
resource "aws_acmpca_certificate" "root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"
  template_arn                = "arn:${data.aws_partition.current.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = var.root_validity_years
  }
}

resource "aws_acmpca_certificate_authority_certificate" "root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root.arn
  certificate               = aws_acmpca_certificate.root.certificate
  certificate_chain         = aws_acmpca_certificate.root.certificate_chain
}

# ---------------------------------------------------------------- Subordinate CA
resource "aws_acmpca_certificate_authority" "subordinate" {
  type       = "SUBORDINATE"
  usage_mode = "GENERAL_PURPOSE" # issues ACM certs that ACM can auto-renew

  certificate_authority_configuration {
    key_algorithm     = "RSA_2048"
    signing_algorithm = "SHA256WITHRSA"

    subject {
      common_name         = var.subordinate_common_name
      organization        = var.organization
      organizational_unit = "Platform PKI"
      country             = var.country
    }
  }

  # OCSP lets clients check revocation without a CRL bucket.
  revocation_configuration {
    ocsp_configuration {
      enabled = true
    }
  }

  permanent_deletion_time_in_days = 30

  lifecycle {
    prevent_destroy = true
  }
}

# Root signs the subordinate's CSR. PathLen0 = the subordinate cannot create further CAs.
resource "aws_acmpca_certificate" "subordinate" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.subordinate.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"
  template_arn                = "arn:${data.aws_partition.current.partition}:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

  validity {
    type  = "YEARS"
    value = var.subordinate_validity_years
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.root]
}

resource "aws_acmpca_certificate_authority_certificate" "subordinate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.subordinate.arn
  certificate               = aws_acmpca_certificate.subordinate.certificate
  certificate_chain         = aws_acmpca_certificate.subordinate.certificate_chain
}

# ---------------------------------------------------------------- RAM share (Subordinate CA only)
resource "aws_ram_resource_share" "subordinate_ca" {
  name                      = "platform-subordinate-ca"
  allow_external_principals = false # organization members only

  tags = { Purpose = "Private TLS for workload accounts" }
}

resource "aws_ram_resource_association" "subordinate_ca" {
  resource_share_arn = aws_ram_resource_share.subordinate_ca.arn
  resource_arn       = aws_acmpca_certificate_authority.subordinate.arn

  depends_on = [aws_acmpca_certificate_authority_certificate.subordinate]
}

# Share with the whole organization, or only with the listed OUs.
resource "aws_ram_principal_association" "this" {
  for_each = toset(length(var.share_with_ou_arns) > 0 ? var.share_with_ou_arns : [var.organization_arn])

  resource_share_arn = aws_ram_resource_share.subordinate_ca.arn
  principal          = each.value
}

variable "domain_name" {
  description = "Primary name on the certificate, e.g. checkout.payments.dev.corp.internal"
  type        = string

  validation {
    condition     = can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name (optionally starting with *.)."
  }
}

variable "subject_alternative_names" {
  type    = list(string)
  default = []
}

variable "certificate_authority_arn" {
  description = "ARN of the RAM-shared Subordinate CA (never the Root CA)"
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm-pca:[a-z0-9-]+:[0-9]{12}:certificate-authority/[0-9a-f-]{36}$", var.certificate_authority_arn))
    error_message = "certificate_authority_arn must be an ACM PCA certificate-authority ARN."
  }
}

variable "key_algorithm" {
  type    = string
  default = "RSA_2048"

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be RSA_2048, EC_prime256v1 or EC_secp384r1."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

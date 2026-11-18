variable "region" {
  description = "Must match the region where spokes request certificates (ACM uses same-region CAs)"
  type        = string
}

variable "organization_arn" {
  description = "arn:aws:organizations::<mgmt-account>:organization/o-xxxx (input, not hardcoded)"
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:organizations::[0-9]{12}:organization/o-[a-z0-9]{10,32}$", var.organization_arn))
    error_message = "organization_arn must be an AWS Organizations organization ARN."
  }
}

variable "share_with_ou_arns" {
  description = "Optional: share only with these OUs instead of the whole organization"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.share_with_ou_arns : can(regex("^arn:aws[a-z-]*:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-[a-z0-9-]+$", a))])
    error_message = "share_with_ou_arns must contain OU ARNs."
  }
}

variable "organization" {
  description = "Certificate subject O="
  type        = string
}

variable "country" {
  description = "Certificate subject C= (2 letters)"
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.country))
    error_message = "country must be a 2-letter ISO code, e.g. US."
  }
}

variable "root_common_name" {
  type    = string
  default = "Corp Platform Root CA"
}

variable "subordinate_common_name" {
  type    = string
  default = "Corp Platform Issuing CA 1"
}

variable "root_validity_years" {
  type    = number
  default = 10
}

variable "subordinate_validity_years" {
  type    = number
  default = 5

  validation {
    condition     = var.subordinate_validity_years >= 1 && var.subordinate_validity_years <= 9
    error_message = "subordinate_validity_years must be 1-9 (shorter than the root)."
  }
}

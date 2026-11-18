variable "region" {
  type = string
}

variable "team" {
  description = "Team key, e.g. payments (used in the state key <team>/<env>/terraform.tfstate)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.team))
    error_message = "team must be 2-20 lowercase letters, digits or hyphens."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "repository_name" {
  description = "Team repo name WITHOUT owner, e.g. app-team-payments-infra (registry key prefix and session tag)"
  type        = string

  validation {
    condition     = can(regex("^app-team-[a-z0-9-]+-infra$", var.repository_name))
    error_message = "repository_name must look like app-team-<name>-infra."
  }
}

variable "spoke_account_id" {
  description = "The team's dedicated account for this environment"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.spoke_account_id))
    error_message = "spoke_account_id must be 12 digits."
  }
}

variable "spoke_bootstrap_role_name" {
  description = "Role the central team uses to reach new accounts (Organizations default shown)"
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "registry_table_name" {
  description = "Output registry_table_name of platform/shared-services"
  type        = string
  default     = "plat-account-registry"
}

variable "codebuild_role_param" {
  description = "SSM parameter (Shared Services) holding the CodeBuild role ARN"
  type        = string
  default     = "/platform/codebuild/role-arn"
}

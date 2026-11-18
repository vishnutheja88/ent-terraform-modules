variable "region" {
  description = "Control-plane region (state, registry, pipelines)"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every control-plane resource and pipeline name"
  type        = string
  default     = "plat"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.name_prefix))
    error_message = "name_prefix must be 2-12 lowercase letters, digits or hyphens."
  }
}

variable "source_provider" {
  description = "CodeConnections provider for team repos: GitHub, GitHubEnterpriseServer, Bitbucket or GitLab"
  type        = string
  default     = "GitHub"

  validation {
    condition     = contains(["GitHub", "GitHubEnterpriseServer", "Bitbucket", "GitLab"], var.source_provider)
    error_message = "source_provider must be GitHub, GitHubEnterpriseServer, Bitbucket or GitLab."
  }
}

variable "teams" {
  description = <<-EOT
    Onboarded application teams. One pipeline is created per team x environment.
    Each team/env also needs a registry item (platform/account-onboarding).
  EOT
  type = map(object({
    repository   = string # "<owner>/app-team-<name>-infra"
    branch       = optional(string, "main")
    environments = optional(list(string), ["dev", "staging", "prod"])
  }))

  validation {
    condition     = alltrue([for t in values(var.teams) : can(regex("^[A-Za-z0-9_.-]+/app-team-[a-z0-9-]+-infra$", t.repository))])
    error_message = "teams.*.repository must look like <owner>/app-team-<name>-infra."
  }

  validation {
    condition     = alltrue(flatten([for t in values(var.teams) : [for e in t.environments : contains(["dev", "staging", "prod"], e)]]))
    error_message = "teams.*.environments may only contain dev, staging and prod."
  }

  validation {
    condition     = alltrue([for k in keys(var.teams) : can(regex("^[a-z][a-z0-9-]{1,19}$", k))])
    error_message = "Team keys must be 2-20 lowercase letters, digits or hyphens."
  }
}

variable "platform_repo_url" {
  description = "HTTPS clone URL of platform-terraform-modules (Stage 1 clones it at the team's platform_version tag)"
  type        = string

  validation {
    condition     = can(regex("^https://[^@\\s]+\\.git$", var.platform_repo_url))
    error_message = "platform_repo_url must be an https://...git URL with no embedded credentials."
  }
}

variable "platform_repo_token_secret_name" {
  description = "Secrets Manager secret (plain string) with a read-only token for platform-terraform-modules"
  type        = string
}

variable "subordinate_ca_arn" {
  description = "Output subordinate_ca_arn of platform/pki; stored in SSM for pipelines"
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm-pca:[a-z0-9-]+:[0-9]{12}:certificate-authority/[0-9a-f-]{36}$", var.subordinate_ca_arn))
    error_message = "subordinate_ca_arn must be an ACM PCA certificate-authority ARN."
  }
}

variable "approver_emails" {
  description = "Receive prod approval requests"
  type        = list(string)
  default     = []
}

variable "notification_emails" {
  description = "Receive success/failure of every pipeline run"
  type        = list(string)
  default     = []
}

variable "terraform_version" {
  type    = string
  default = "1.12.2"

  validation {
    condition     = can(regex("^1\\.(1[1-9]|[2-9][0-9])\\.[0-9]+$", var.terraform_version))
    error_message = "terraform_version must be >= 1.11 (the stack requires >= 1.11.1)."
  }
}

variable "checkov_version" {
  description = "Pinned Checkov version installed in the plan stage"
  type        = string
  default     = "3.4.5"
}

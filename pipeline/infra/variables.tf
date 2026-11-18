variable "region" {
  type    = string
  default = "us-east-1"
}

variable "source_provider" {
  description = "CodeConnections provider: GitHub or Bitbucket"
  type        = string
  default     = "GitHub"
}

variable "repository_id" {
  description = "owner/repo, e.g. vishnutheja88/ent-terraform-modules"
  type        = string
}

variable "branch" {
  type    = string
  default = "main"
}

variable "environments" {
  description = "One pipeline per env folder under envs/"
  type = map(object({
    require_approval = bool
  }))
  default = {
    dev  = { require_approval = false }
    prod = { require_approval = true }
  }
}

variable "shared_trigger_paths" {
  description = "Changes here re-run every env pipeline"
  type        = list(string)
  default     = []
  # e.g. ["blueprint/**", "modules/**"] — off by default so a module change
  # doesn't auto-roll prod; bump module refs per env instead.
}

variable "target_deploy_role_arns" {
  description = "Cross-account deploy roles CodeBuild may assume (account_role in values.yaml)"
  type        = list(string)
  default     = ["arn:aws:iam::*:role/tf-deploy"]
}

variable "same_account_deploy_policy_arns" {
  description = <<-EOT
    Policies for same-account deploys (no account_role in values.yaml).
    EKS + IAM + Route53 need broad rights, so the lab default is AdministratorAccess.
    In an enterprise, leave this empty and deploy through a scoped cross-account tf-deploy role.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "approver_emails" {
  type    = list(string)
  default = []
}

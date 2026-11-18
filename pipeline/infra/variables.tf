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

variable "pipelines" {
  description = <<-EOT
    One CodePipeline per values file. The blueprint is read from the file's "blueprint:" key.
    Add an app: create envs/<env>/apps/<app>.yaml and add an entry here.
  EOT
  type = map(object({
    values_file      = string
    require_approval = bool
  }))
  default = {
    dev-platform  = { values_file = "envs/dev/platform.yaml", require_approval = false }
    prod-platform = { values_file = "envs/prod/platform.yaml", require_approval = true }
    dev-orders    = { values_file = "envs/dev/apps/orders.yaml", require_approval = false }
  }
}

variable "shared_trigger_paths" {
  description = "Changes here re-run every env pipeline"
  type        = list(string)
  default     = []
  # e.g. ["blueprints/**", "modules/**"] — off by default so a module change
  # doesn't auto-roll prod; bump module refs per env instead.
}

variable "target_deploy_role_arns" {
  description = "Cross-account deploy roles CodeBuild may assume (account_role in the values file)"
  type        = list(string)
  default     = ["arn:aws:iam::*:role/tf-deploy"]
}

variable "same_account_deploy_policy_arns" {
  description = <<-EOT
    Policies for same-account deploys (no account_role in the values file).
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

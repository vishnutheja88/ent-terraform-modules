################################################################################
# platform/shared-services  -  the Control Plane, run by the central team in the
# Shared Services account. Creates:
#   storage.tf        KMS key, Terraform state bucket + DynamoDB lock table,
#                     DynamoDB Account Registry, pipeline artifact bucket
#   iam.tf            CodeBuild + CodePipeline service roles (least privilege)
#   codebuild.tf      3 CodeBuild projects with CENTRAL buildspecs (teams cannot edit them)
#   pipelines.tf      one QUEUED CodePipeline V2 per team repo x environment
#   notifications.tf  SNS approval topic, EventBridge run notifications
################################################################################

terraform {
  required_version = ">= 1.11.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
  }
  backend "s3" {} # bootstrap state; see README
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { ManagedBy = "platform-terraform", Component = "shared-services" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  prefix     = var.name_prefix
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # One pipeline per (team repo, environment). Key: "<team>-<env>", e.g. "payments-prod".
  pipelines = merge([
    for team, t in var.teams : {
      for env in t.environments : "${team}-${env}" => {
        team        = team
        environment = env
        repository  = t.repository # "<owner>/app-team-<name>-infra"
        branch      = t.branch
      }
    }
  ]...)
}

# Where pipelines read the Subordinate CA ARN at run time (no ARN in code or buildspecs).
resource "aws_ssm_parameter" "subordinate_ca_arn" {
  name        = "/platform/pki/subordinate-ca-arn"
  description = "RAM-shared Subordinate CA from the Security/PKI account"
  type        = "String"
  value       = var.subordinate_ca_arn
}

# Account onboarding reads this to build each spoke role's trust policy.
resource "aws_ssm_parameter" "codebuild_role_arn" {
  name        = "/platform/codebuild/role-arn"
  description = "Only principal allowed to assume PlatformTerraformDeployRole in spokes"
  type        = "String"
  value       = aws_iam_role.codebuild.arn
}

resource "aws_codestarconnections_connection" "git" {
  name          = "${local.prefix}-git"
  provider_type = var.source_provider
}

data "aws_secretsmanager_secret" "platform_repo_token" {
  name = var.platform_repo_token_secret_name
}

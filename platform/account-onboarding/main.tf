################################################################################
# platform/account-onboarding  -  run once per (team, environment) spoke account
# by the central team. One state file per spoke (see README).
#
# In the SPOKE account:
#   - PlatformWorkloadBoundary   permissions boundary for every role Terraform creates
#   - PlatformTerraformDeployRole  trusted ONLY by the Shared Services CodeBuild role,
#                                  ONLY with this spoke's ExternalId and session tags
# In SHARED SERVICES:
#   - the DynamoDB Account Registry item "<repo_name>#<environment>"
################################################################################

terraform {
  required_version = ">= 1.11.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.59, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
  backend "s3" {} # key e.g. onboarding/payments-prod.tfstate
}

# Shared Services (where this runs)
provider "aws" {
  alias  = "shared"
  region = var.region
}

data "aws_partition" "current" {
  provider = aws.shared
}

# Spoke account, reached through the Organizations bootstrap role.
provider "aws" {
  alias  = "spoke"
  region = var.region

  assume_role {
    role_arn     = "arn:${data.aws_partition.current.partition}:iam::${var.spoke_account_id}:role/${var.spoke_bootstrap_role_name}"
    session_name = "platform-onboarding"
  }

  allowed_account_ids = [var.spoke_account_id]

  default_tags {
    tags = { ManagedBy = "platform-terraform", Component = "account-onboarding", Team = var.team }
  }
}

locals {
  partition     = data.aws_partition.current.partition
  registry_key  = "${var.repository_name}#${var.environment}"
  tf_state_key  = "${var.team}/${var.environment}/terraform.tfstate"
  deploy_role   = "PlatformTerraformDeployRole"
  boundary_name = "PlatformWorkloadBoundary"
  boundary_arn  = "arn:${local.partition}:iam::${var.spoke_account_id}:policy/${local.boundary_name}"
  deploy_policy = "arn:${local.partition}:iam::${var.spoke_account_id}:policy/PlatformTerraformDeployPolicy"
}

# Only principal that may assume the spoke role (published by platform/shared-services).
data "aws_ssm_parameter" "codebuild_role_arn" {
  provider = aws.shared
  name     = var.codebuild_role_param
}

# Per-spoke secret shared only between the registry and the trust policy.
resource "random_uuid" "external_id" {}

# ---------------------------------------------------------------- Spoke: workload boundary
# The most any role created by the stack (ECS task/exec roles, flow-log role) can ever do.
data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid    = "WorkloadRuntime"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
      "secretsmanager:GetSecretValue", "kms:Decrypt", "ssm:GetParameter", "ssm:GetParameters",
      "s3:GetObject", "s3:PutObject", "s3:ListBucket",
      "cloudwatch:PutMetricData", "xray:PutTraceSegments", "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NeverIamOrOrg"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "account:*", "sts:AssumeRole"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  provider = aws.spoke
  name     = local.boundary_name
  policy   = data.aws_iam_policy_document.workload_boundary.json
}

# ---------------------------------------------------------------- Spoke: deploy role
data "aws_iam_policy_document" "deploy_trust" {
  # The CodeBuild role may assume this role only with the right ExternalId
  # and session tags naming THIS team's repo and THIS environment.
  statement {
    sid     = "SharedServicesCodeBuildOnly"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_ssm_parameter.codebuild_role_arn.value]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [random_uuid.external_id.result]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/platform-repo"
      values   = [var.repository_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/platform-env"
      values   = [var.environment]
    }
  }

  statement {
    sid     = "AllowPlatformSessionTags"
    actions = ["sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_ssm_parameter.codebuild_role_arn.value]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/platform-repo"
      values   = [var.repository_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/platform-env"
      values   = [var.environment]
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  # Create/modify roles ONLY if they carry the workload boundary.
  statement {
    sid = "RolesMustHaveBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePermissionsBoundary",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
    ]
    resources = ["arn:${local.partition}:iam::${var.spoke_account_id}:role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid = "RoleHousekeeping"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole",
    ]
    resources = ["arn:${local.partition}:iam::${var.spoke_account_id}:role/*"]
  }

  statement {
    sid = "CustomerManagedPolicies"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = ["arn:${local.partition}:iam::${var.spoke_account_id}:policy/*"]
  }

  statement {
    sid       = "PassRolesOnlyToWorkloadServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${var.spoke_account_id}:role/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "vpc-flow-logs.amazonaws.com", "rds.amazonaws.com", "monitoring.rds.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com", "rds.amazonaws.com"]
    }
  }

  # Nobody (including this role) can loosen the guardrails.
  statement {
    sid       = "ProtectGuardrails"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = [
      "arn:${local.partition}:iam::${var.spoke_account_id}:role/${local.deploy_role}",
      "arn:${local.partition}:iam::${var.spoke_account_id}:role/${var.spoke_bootstrap_role_name}",
      local.boundary_arn,
      local.deploy_policy,
    ]
  }

  statement {
    sid       = "NeverRemoveBoundaries"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  # ACM must be able to use the RAM-shared Subordinate CA from this account.
  statement {
    sid = "PrivateCertificates"
    actions = [
      "acm:RequestCertificate", "acm:DescribeCertificate", "acm:DeleteCertificate", "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate", "acm-pca:DescribeCertificateAuthority",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy" {
  provider = aws.spoke
  name     = "PlatformTerraformDeployPolicy"
  policy   = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role" "deploy" {
  provider             = aws.spoke
  name                 = local.deploy_role
  description          = "Assumed by the platform pipeline for ${var.repository_name} (${var.environment})"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

# PowerUserAccess covers the AWS services the modules use (EC2/VPC, ECS, ELB, RDS,
# Logs, Secrets Manager, KMS ...) and excludes IAM; the policy above adds the
# narrow IAM rights. Swap for a tighter custom policy if your org requires it.
resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  provider   = aws.spoke
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "deploy_iam" {
  provider   = aws.spoke
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

# ---------------------------------------------------------------- Shared Services: registry item
resource "aws_dynamodb_table_item" "registry" {
  provider   = aws.shared
  table_name = var.registry_table_name
  hash_key   = "registry_key"

  item = jsonencode({
    registry_key           = { S = local.registry_key }
    team                   = { S = var.team }
    environment            = { S = var.environment }
    target_account_id      = { S = var.spoke_account_id }
    cross_account_role_arn = { S = aws_iam_role.deploy.arn }
    tf_state_key           = { S = local.tf_state_key }
    external_id            = { S = random_uuid.external_id.result }
  })
}

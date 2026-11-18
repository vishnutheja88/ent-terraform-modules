#####################################################################
# Bootstraps the delivery platform (run once, locally, by platform team):
#   - S3 state bucket + S3 artifact bucket
#   - CodeConnections connection to GitHub / Bitbucket
#   - One CodeBuild project (shared buildspec)
#   - One CodePipeline V2 per env, triggered only by envs/<env>/** changes
#####################################################################

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  prefix     = "ent-tf"
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------- Buckets ----------------
resource "aws_s3_bucket" "state" {
  bucket = "${local.prefix}-tfstate-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.prefix}-artifacts-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each                = { state = aws_s3_bucket.state.id, artifacts = aws_s3_bucket.artifacts.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- Source connection ----------------
# After apply: AWS Console -> Developer Tools -> Settings -> Connections
# -> select this connection -> "Update pending connection" (one-time OAuth handshake)
resource "aws_codestarconnections_connection" "src" {
  name          = "${local.prefix}-src"
  provider_type = var.source_provider # "GitHub" or "Bitbucket"
}

# ---------------- IAM: CodeBuild ----------------
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.prefix}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    sid     = "StateAndArtifacts"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*",
      aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }
  statement {
    sid       = "AssumeTargetDeployRoles"
    actions   = ["sts:AssumeRole"]
    resources = var.target_deploy_role_arns
  }
  statement {
    sid       = "BitbucketTokenOptional"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:bitbucket/*"]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# Same-account deploys (no account_role in values.yaml) need resource permissions.
# Tighten these for real use, or deploy cross-account only.
resource "aws_iam_role_policy_attachment" "codebuild_deploy" {
  for_each   = toset(var.same_account_deploy_policy_arns)
  role       = aws_iam_role.codebuild.name
  policy_arn = each.value
}

# ---------------- CodeBuild ----------------
resource "aws_codebuild_project" "tf" {
  name          = "${local.prefix}-terraform"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 60

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = aws_s3_bucket.state.bucket
    }
    environment_variable {
      name  = "TF_STATE_REGION"
      value = var.region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "pipeline/buildspec.yml"
  }
}

# ---------------- IAM: CodePipeline ----------------
data "aws_iam_policy_document" "pipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  name               = "${local.prefix}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume.json
}

data "aws_iam_policy_document" "pipeline" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }
  statement {
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [aws_codebuild_project.tf.arn]
  }
  statement {
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.src.arn]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.approvals.arn]
  }
}

resource "aws_iam_role_policy" "pipeline" {
  role   = aws_iam_role.pipeline.id
  policy = data.aws_iam_policy_document.pipeline.json
}

# ---------------- Approval notifications ----------------
resource "aws_sns_topic" "approvals" {
  name = "${local.prefix}-approvals"
}

resource "aws_sns_topic_subscription" "approvers" {
  for_each  = toset(var.approver_emails)
  topic_arn = aws_sns_topic.approvals.arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------- One pipeline per environment ----------------
resource "aws_codepipeline" "env" {
  for_each = var.environments

  name          = "${local.prefix}-${each.key}"
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Only run when THIS env's values change (or shared blueprint/modules change)
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
        file_paths {
          includes = concat(["envs/${each.key}/**"], var.shared_trigger_paths)
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["src"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.src.arn
        FullRepositoryId     = var.repository_id
        BranchName           = var.branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name             = "ValidateAndPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["src"]
      output_artifacts = ["plan"]
      configuration = {
        ProjectName = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([
          { name = "ENV", value = each.key, type = "PLAINTEXT" },
          { name = "STAGE", value = "plan", type = "PLAINTEXT" },
        ])
      }
    }
  }

  dynamic "stage" {
    for_each = each.value.require_approval ? [1] : []
    content {
      name = "Approve"
      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"
        configuration = {
          NotificationArn = aws_sns_topic.approvals.arn
          CustomData      = "Review the plan in the Plan stage CodeBuild logs (plan.txt) for env=${each.key}"
        }
      }
    }
  }

  stage {
    name = "Apply"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan"]
      configuration = {
        ProjectName = aws_codebuild_project.tf.name
        EnvironmentVariables = jsonencode([
          { name = "ENV", value = each.key, type = "PLAINTEXT" },
          { name = "STAGE", value = "apply", type = "PLAINTEXT" },
        ])
      }
    }
  }
}

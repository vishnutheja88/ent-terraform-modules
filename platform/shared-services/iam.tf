################################################################################
# Service roles. CodeBuild is the ONLY principal spoke roles trust.
################################################################################

# ---------------------------------------------------------------- CodeBuild
data "aws_iam_policy_document" "codebuild_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.prefix}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }

  statement {
    sid       = "PipelineArtifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.this["artifacts"].arn}/*"]
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.this["state"].arn}/*"]
  }

  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.this["state"].arn, aws_s3_bucket.this["artifacts"].arn]
  }

  statement {
    sid       = "StateLocks"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }

  statement {
    sid       = "RegistryReadOnly"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.registry.arn]
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.platform.arn]
  }

  statement {
    sid       = "PlatformParameters"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/platform/*"]
  }

  statement {
    sid       = "PlatformRepoToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.platform_repo_token.arn]
  }

  # Can only assume roles NAMED PlatformTerraformDeployRole, and only with the
  # two platform session tags. Each spoke's trust policy then pins the exact
  # repo/env tag values and ExternalId, so Team A's run can't use Team B's role.
  statement {
    sid       = "AssumeSpokeDeployRoles"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:${local.partition}:iam::*:role/PlatformTerraformDeployRole"]
  }

  statement {
    sid       = "TagSpokeSessions"
    actions   = ["sts:TagSession"]
    resources = ["arn:${local.partition}:iam::*:role/PlatformTerraformDeployRole"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["platform-repo", "platform-env"]
    }
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "platform-codebuild"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

# ---------------------------------------------------------------- CodePipeline
data "aws_iam_policy_document" "codepipeline_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${local.prefix}-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_trust.json
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid       = "Artifacts"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
    resources = [aws_s3_bucket.this["artifacts"].arn, "${aws_s3_bucket.this["artifacts"].arn}/*"]
  }

  statement {
    sid       = "Kms"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.platform.arn]
  }

  statement {
    sid       = "RunBuilds"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
    resources = [for p in aws_codebuild_project.stage : p.arn]
  }

  statement {
    sid       = "UseGitConnection"
    actions   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
    resources = [aws_codestarconnections_connection.git.arn]
  }

  statement {
    sid       = "ApprovalNotifications"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.approvals.arn]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "platform-codepipeline"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}

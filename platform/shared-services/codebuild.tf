################################################################################
# Three CodeBuild projects, shared by every pipeline. The buildspecs are stored
# HERE (inline), not in team repos, so app teams cannot change how they deploy.
################################################################################

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/platform/codebuild"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.platform.arn
}

locals {
  stages = {
    assemble = "stage1-assemble.yml" # Stage 1: metadata, registry lookup, clone platform tag, build /workspace
    plan     = "stage2-plan.yml"     # Stage 2: assume spoke role, init, plan, Checkov
    apply    = "stage3-apply.yml"    # Stage 3: re-assume, apply the saved tfplan
  }

  # Same environment for all three; nothing here is an account id or CA ARN literal.
  codebuild_env = {
    REGISTRY_TABLE       = aws_dynamodb_table.registry.name
    TF_STATE_BUCKET      = aws_s3_bucket.this["state"].bucket
    TF_STATE_REGION      = var.region
    TF_LOCK_TABLE        = aws_dynamodb_table.tf_lock.name
    TF_STATE_KMS_KEY_ARN = aws_kms_key.platform.arn
    PLATFORM_REPO_URL    = var.platform_repo_url
    SUBORDINATE_CA_PARAM = aws_ssm_parameter.subordinate_ca_arn.name
    TF_VERSION           = var.terraform_version
    CHECKOV_VERSION      = var.checkov_version
  }
}

resource "aws_codebuild_project" "stage" {
  for_each = local.stages

  name           = "${local.prefix}-${each.key}"
  description    = "Self-service IaC: ${each.key}"
  service_role   = aws_iam_role.codebuild.arn
  encryption_key = aws_kms_key.platform.arn
  build_timeout  = each.key == "assemble" ? 15 : 60

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/${each.value}")
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type         = "LINUX_CONTAINER"

    dynamic "environment_variable" {
      for_each = local.codebuild_env
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }

    # Token used only by Stage 1 to clone platform-terraform-modules at a tag.
    environment_variable {
      name  = "PLATFORM_REPO_TOKEN"
      value = data.aws_secretsmanager_secret.platform_repo_token.name
      type  = "SECRETS_MANAGER"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = each.key
    }
  }
}

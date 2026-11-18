################################################################################
# One CodePipeline V2 per (team repo, environment).
#
# Stage 1 trigger: a push to the team repo's branch that changes <env>/** fires
# ONLY that environment's pipeline (CodeConnections webhook -> V2 trigger with a
# file-path filter). Teams never block each other because each pipeline is
# separate; within one pipeline, QUEUED mode applies pushes in order so two
# applies never race on the same state file.
################################################################################

resource "aws_codepipeline" "team" {
  for_each = local.pipelines

  name           = "${local.prefix}-${each.key}" # e.g. plat-payments-prod
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    location = aws_s3_bucket.this["artifacts"].bucket
    type     = "S3"

    encryption_key {
      id   = aws_kms_key.platform.arn
      type = "KMS"
    }
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [each.value.branch]
        }
        file_paths {
          includes = ["${each.value.environment}/**"]
        }
      }
    }
  }

  # ------------------------------------------------ Source (+ metadata capture)
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables" # exposes FullRepositoryName, BranchName, CommitId
      output_artifacts = ["team_repo"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.git.arn
        FullRepositoryId     = each.value.repository
        BranchName           = each.value.branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  # ------------------------------------------------ Stage 1: assemble workspace
  stage {
    name = "Assemble"
    action {
      name             = "AssembleWorkspace"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["team_repo"]
      output_artifacts = ["workspace"]
      configuration = {
        ProjectName = aws_codebuild_project.stage["assemble"].name
        EnvironmentVariables = jsonencode([
          { name = "ENVIRONMENT", value = each.value.environment, type = "PLAINTEXT" },
          { name = "VALUES_PATH", value = "${each.value.environment}/values.yaml", type = "PLAINTEXT" },
          { name = "REPO_FULL_NAME", value = "#{SourceVariables.FullRepositoryName}", type = "PLAINTEXT" },
          { name = "BRANCH", value = "#{SourceVariables.BranchName}", type = "PLAINTEXT" },
          { name = "COMMIT_ID", value = "#{SourceVariables.CommitId}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  # ------------------------------------------------ Stage 2: plan + policy as code
  stage {
    name = "Plan"
    action {
      name             = "PlanAndScan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "PlanVariables" # exports PLAN_ADD / PLAN_CHANGE / PLAN_DESTROY
      input_artifacts  = ["workspace"]
      output_artifacts = ["planned_workspace"]
      configuration = {
        ProjectName = aws_codebuild_project.stage["plan"].name
      }
    }
  }

  # ------------------------------------------------ Stage 4: approval (prod only)
  dynamic "stage" {
    for_each = each.value.environment == "prod" ? [1] : []
    content {
      name = "Approve"
      action {
        name     = "ProdApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"
        configuration = {
          NotificationArn = aws_sns_topic.approvals.arn
          CustomData      = "PROD deploy for #{SourceVariables.FullRepositoryName} @ #{SourceVariables.CommitId}: +#{PlanVariables.PLAN_ADD} add, ~#{PlanVariables.PLAN_CHANGE} change, -#{PlanVariables.PLAN_DESTROY} destroy. Full plan: Plan stage logs (tfplan.txt)."
        }
      }
    }
  }

  # ------------------------------------------------ Stage 5: cross-account apply
  stage {
    name = "Apply"
    action {
      name            = "ApplySavedPlan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["planned_workspace"]
      configuration = {
        ProjectName = aws_codebuild_project.stage["apply"].name
      }
    }
  }
}

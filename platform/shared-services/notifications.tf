################################################################################
# SNS topics (KMS-encrypted) + EventBridge rule for pipeline outcomes
################################################################################

resource "aws_sns_topic" "approvals" {
  name              = "${local.prefix}-prod-approvals"
  kms_master_key_id = aws_kms_key.platform.arn
}

resource "aws_sns_topic_subscription" "approvers" {
  for_each  = toset(var.approver_emails)
  topic_arn = aws_sns_topic.approvals.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic" "runs" {
  name              = "${local.prefix}-pipeline-runs"
  kms_master_key_id = aws_kms_key.platform.arn
}

resource "aws_sns_topic_subscription" "runs" {
  for_each  = toset(var.notification_emails)
  topic_arn = aws_sns_topic.runs.arn
  protocol  = "email"
  endpoint  = each.value
}

data "aws_iam_policy_document" "runs_topic" {
  statement {
    sid       = "AllowEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.runs.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.pipeline_outcome.arn]
    }
  }
}

resource "aws_sns_topic_policy" "runs" {
  arn    = aws_sns_topic.runs.arn
  policy = data.aws_iam_policy_document.runs_topic.json
}

# Every platform pipeline that succeeds or fails sends a one-line summary.
resource "aws_cloudwatch_event_rule" "pipeline_outcome" {
  name        = "${local.prefix}-pipeline-outcome"
  description = "Self-service IaC pipeline finished"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      state    = ["SUCCEEDED", "FAILED"]
      pipeline = [{ prefix = "${local.prefix}-" }]
    }
  })
}

resource "aws_cloudwatch_event_target" "pipeline_outcome" {
  rule = aws_cloudwatch_event_rule.pipeline_outcome.name
  arn  = aws_sns_topic.runs.arn

  input_transformer {
    input_paths = {
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
      execution = "$.detail.execution-id"
    }
    input_template = "\"Pipeline <pipeline> finished: <state> (execution <execution>)\""
  }
}

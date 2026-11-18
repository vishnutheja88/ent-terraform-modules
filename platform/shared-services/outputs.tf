output "codebuild_role_arn" {
  description = "Also published to SSM /platform/codebuild/role-arn for account onboarding"
  value       = aws_iam_role.codebuild.arn
}

output "registry_table_name" {
  value = aws_dynamodb_table.registry.name
}

output "state_bucket" {
  value = aws_s3_bucket.this["state"].bucket
}

output "lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}

output "kms_key_arn" {
  value = aws_kms_key.platform.arn
}

output "connection_arn" {
  description = "Complete the pending handshake in the console once (Developer Tools > Connections)"
  value       = aws_codestarconnections_connection.git.arn
}

output "pipelines" {
  value = { for k, p in aws_codepipeline.team : k => p.name }
}

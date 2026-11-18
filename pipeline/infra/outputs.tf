output "connection_arn" {
  description = "Complete the pending handshake for this connection in the AWS console"
  value       = aws_codestarconnections_connection.src.arn
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "pipelines" {
  value = { for k, p in aws_codepipeline.env : k => p.name }
}

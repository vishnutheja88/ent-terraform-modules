output "registry_key" {
  value = local.registry_key
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "tf_state_key" {
  value = local.tf_state_key
}

output "workload_boundary_arn" {
  value = aws_iam_policy.workload_boundary.arn
}

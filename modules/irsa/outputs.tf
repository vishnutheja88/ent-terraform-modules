output "arn" {
  description = "Put this in the ServiceAccount annotation eks.amazonaws.com/role-arn"
  value       = module.this.arn
}

output "name" {
  value = module.this.name
}

output "policy_arn" {
  value = module.this.iam_policy_arn
}

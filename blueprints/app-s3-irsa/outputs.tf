output "bucket_name" {
  value = module.s3.name
}

output "bucket_arn" {
  value = module.s3.arn
}

output "role_arn" {
  description = "Annotate the ServiceAccount with this"
  value       = module.irsa.arn
}

output "service_account_manifest" {
  description = "Ready-to-apply ServiceAccount for the app team"
  value       = <<-EOT
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ${local.cfg.irsa.service_account}
      namespace: ${local.cfg.irsa.namespace}
      annotations:
        eks.amazonaws.com/role-arn: ${module.irsa.arn}
  EOT
}

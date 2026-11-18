output "stack_name" {
  value = local.name
}

output "enabled_components" {
  value = {
    networking = local.networking_on
    tls        = local.tls_on
    ecs        = local.ecs_on
    rds        = local.rds_on
  }
}

output "vpc_id" {
  value = one(module.networking[*].vpc_id)
}

output "private_subnet_ids" {
  value = one(module.networking[*].private_subnet_ids)
}

output "certificate_arn" {
  value = one(module.tls[*].certificate_arn)
}

output "alb_dns_name" {
  value = one(module.ecs[*].alb_dns_name)
}

output "ecs_cluster_name" {
  value = one(module.ecs[*].cluster_name)
}

output "rds_endpoint" {
  value = one(module.rds[*].endpoint)
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN; reference it from ecs.services.*.secrets"
  value       = one(module.rds[*].master_user_secret_arn)
}

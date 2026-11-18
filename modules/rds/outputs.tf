output "endpoint" {
  value = module.db.db_instance_endpoint
}

output "address" {
  value = module.db.db_instance_address
}

output "port" {
  value = module.db.db_instance_port
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the master password"
  value       = module.db.db_instance_master_user_secret_arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}

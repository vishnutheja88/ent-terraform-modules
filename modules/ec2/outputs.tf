output "instance_ids" {
  value = { for k, m in module.instance : k => m.id }
}

output "private_ips" {
  value = { for k, m in module.instance : k => m.private_ip }
}

output "public_ips" {
  value = { for k, m in module.instance : k => m.public_ip }
}

output "security_group_id" {
  value = module.sg.id
}

output "iam_role_arns" {
  value = { for k, m in module.instance : k => m.iam_role_arn }
}

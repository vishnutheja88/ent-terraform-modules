output "enabled_components" {
  value = {
    vpc     = local.vpc_on
    igw     = local.igw_on
    nat     = local.nat_on
    ec2     = local.ec2_on
    iam     = local.iam_on
    route53 = local.route53_on
    eks     = local.eks_on
  }
}

output "vpc_id" {
  value = local.vpc_id
}

output "private_subnet_ids" {
  value = local.private_subnet_ids
}

output "public_subnet_ids" {
  value = local.public_subnet_ids
}

output "ec2_instance_ids" {
  value = one(module.ec2[*].instance_ids)
}

output "ec2_private_ips" {
  value = one(module.ec2[*].private_ips)
}

output "iam_role_arns" {
  value = { for k, m in module.iam_role : k => m.arn }
}

output "eks_cluster_name" {
  value = one(module.eks[*].cluster_name)
}

output "eks_cluster_endpoint" {
  value = one(module.eks[*].cluster_endpoint)
}

output "eks_update_kubeconfig" {
  value = local.eks_on ? "aws eks update-kubeconfig --region ${local.cfg.region} --name ${local.eks_name}" : null
}

output "route53_zone_id" {
  value = one(module.route53[*].zone_id)
}

output "route53_name_servers" {
  value = one(module.route53[*].name_servers)
}

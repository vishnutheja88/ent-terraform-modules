output "vpc_id" {
  value = module.this.vpc_id
}

output "vpc_cidr_block" {
  value = module.this.vpc_cidr_block
}

output "public_subnet_ids" {
  value = module.this.public_subnets
}

output "private_subnet_ids" {
  value = module.this.private_subnets
}

output "igw_id" {
  value = module.this.igw_id
}

output "azs" {
  value = local.azs
}

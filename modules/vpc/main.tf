############################################################
# Wrapper: org-standard VPC on top of terraform-aws-modules/vpc
# Small, stable interface for the values file; upstream has ~250 inputs.
############################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20s from a /16: public 0..3, private 8..11 (room to grow)
  public_subnets  = var.create_igw ? [for i, _ in local.azs : cidrsubnet(var.cidr, 4, i)] : []
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.cidr, 4, i + 8)]

  # Tags EKS/ALB controller use to discover subnets
  eks_tags = var.eks_cluster_name == null ? {} : { "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared" }
}

module "this" {
  source = "../../upstream/terraform-aws-vpc"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  create_igw         = var.create_igw
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # Org standards (not exposed to app teams)
  enable_dns_hostnames          = true
  enable_dns_support            = true
  manage_default_security_group = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = var.enable_flow_log
  create_flow_log_cloudwatch_log_group            = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = 30

  public_subnet_tags  = merge(local.eks_tags, { "kubernetes.io/role/elb" = "1", Tier = "public" })
  private_subnet_tags = merge(local.eks_tags, { "kubernetes.io/role/internal-elb" = "1", Tier = "private" })

  tags = var.tags
}

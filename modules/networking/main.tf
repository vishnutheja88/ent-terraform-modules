################################################################################
# modules/networking
# Platform-standard VPC for a spoke account, on top of the vendored
# terraform-aws-modules/vpc. Three tiers per AZ:
#   public   (/20s)  - internet-facing ALBs and NAT gateways only
#   private  (/20s)  - ECS tasks
#   database (/24s)  - RDS, no route to the internet
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Carve the VPC CIDR the same way in every account so teams can predict ranges.
  # /16 example: public 10.x.0-3.0/20, private 10.x.128-191.0/20, database 10.x.240-243.0/24
  public_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]
  database_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 240)]

  enable_nat = var.nat_gateway != "none"
}

module "vpc" {
  source = "../../upstream/terraform-aws-vpc"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.database_subnets

  # The DB subnet group is created here and handed to modules/rds.
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = false # databases never reach the internet

  enable_nat_gateway     = local.enable_nat
  single_nat_gateway     = var.nat_gateway == "single"
  one_nat_gateway_per_az = var.nat_gateway == "per_az"

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Lock down the default SG: nothing should use it.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = var.enable_flow_log
  create_flow_log_cloudwatch_log_group            = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
  vpc_flow_log_permissions_boundary               = var.permissions_boundary_arn
  flow_log_cloudwatch_log_group_retention_in_days = 90

  public_subnet_tags   = { Tier = "public" }
  private_subnet_tags  = { Tier = "private" }
  database_subnet_tags = { Tier = "database" }

  tags = var.tags
}

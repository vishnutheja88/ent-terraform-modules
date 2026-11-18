##########################################################################
# Blueprint = Rafay "Environment Template"
# values.yaml toggles  ->  which wrapper modules run  ->  upstream modules
##########################################################################

locals {
  cfg  = yamldecode(file(var.values_file))
  env  = local.cfg.env
  name = "${try(local.cfg.name_prefix, "ent")}-${local.env}"

  vpc_on     = try(local.cfg.vpc.enabled, false)
  igw_on     = try(local.cfg.igw.enabled, false)
  nat_on     = try(local.cfg.vpc.nat_gateway, false)
  ec2_on     = try(local.cfg.ec2.enabled, false)
  iam_on     = try(local.cfg.iam.enabled, false)
  route53_on = try(local.cfg.route53.enabled, false)
  eks_on     = try(local.cfg.eks.enabled, false)

  eks_name = "${local.name}-eks"

  # Known at plan time (no module outputs) so the rules below never form a cycle
  has_network = local.vpc_on || try(local.cfg.existing_network.vpc_id, null) != null

  tags = merge(
    {
      Environment = local.env
      ManagedBy   = "terraform"
      Blueprint   = "ent-terraform-modules"
    },
    try(local.cfg.tags, {})
  )

  # Network inputs: from our VPC, or from an existing VPC listed in values.yaml
  vpc_id             = local.vpc_on ? one(module.vpc[*].vpc_id) : try(local.cfg.existing_network.vpc_id, null)
  private_subnet_ids = local.vpc_on ? one(module.vpc[*].private_subnet_ids) : tolist(try(local.cfg.existing_network.private_subnet_ids, []))
  public_subnet_ids  = local.vpc_on ? one(module.vpc[*].public_subnet_ids) : tolist(try(local.cfg.existing_network.public_subnet_ids, []))

  ec2_public     = try(local.cfg.ec2.public, false)
  ec2_subnet_ids = local.ec2_public ? local.public_subnet_ids : local.private_subnet_ids
}

# ---------------- Dependency rules: fail at plan, not halfway through apply ----------------
resource "terraform_data" "rules" {
  lifecycle {
    precondition {
      condition     = !(local.igw_on && !local.vpc_on)
      error_message = "igw.enabled=true requires vpc.enabled=true."
    }
    precondition {
      condition     = !(local.nat_on && !local.igw_on)
      error_message = "vpc.nat_gateway=true requires igw.enabled=true (NAT lives in public subnets)."
    }
    precondition {
      condition     = !(local.ec2_on && !local.has_network)
      error_message = "ec2.enabled=true needs vpc.enabled=true or existing_network.vpc_id + subnet ids."
    }
    precondition {
      condition     = !(local.ec2_public && !local.igw_on)
      error_message = "ec2.public=true requires igw.enabled=true."
    }
    precondition {
      condition     = !(local.eks_on && !local.has_network)
      error_message = "eks.enabled=true needs vpc.enabled=true or existing_network."
    }
    precondition {
      condition     = !(local.eks_on && local.vpc_on && !local.nat_on)
      error_message = "eks.enabled=true with a new VPC requires vpc.nat_gateway=true so nodes can pull images."
    }
    precondition {
      condition     = !(local.route53_on && try(local.cfg.route53.private, true) && !local.has_network)
      error_message = "A private route53 zone needs a VPC (vpc.enabled=true or existing_network.vpc_id)."
    }
  }
}

# ---------------- Modules (wrappers -> vendored upstream) ----------------
# Consuming this repo from another repo / Bitbucket? Use pinned git sources, e.g.
# source = "git::https://github.com/vishnutheja88/ent-terraform-modules.git//modules/vpc?ref=vpc/v1.0.0"

module "vpc" {
  count  = local.vpc_on ? 1 : 0
  source = "../modules/vpc"

  name               = local.name
  cidr               = local.cfg.vpc.cidr
  az_count           = try(local.cfg.vpc.az_count, 2)
  create_igw         = local.igw_on
  enable_nat_gateway = local.nat_on
  single_nat_gateway = try(local.cfg.vpc.single_nat_gateway, true)
  enable_flow_log    = try(local.cfg.vpc.flow_logs, false)
  eks_cluster_name   = local.eks_on ? local.eks_name : null
  tags               = local.tags

  depends_on = [terraform_data.rules]
}

module "iam_role" {
  source   = "../modules/iam-role"
  for_each = { for k, v in try(local.cfg.iam.roles, {}) : k => v if local.iam_on }

  name                     = "${local.name}-${each.key}"
  description              = try(each.value.description, "Role ${each.key} for ${local.env}")
  trusted_services         = try(each.value.trusted_services, [])
  trusted_role_arns        = try(each.value.trusted_role_arns, [])
  policy_arns              = try(each.value.policy_arns, {})
  create_instance_profile  = try(each.value.instance_profile, false)
  permissions_boundary_arn = try(local.cfg.iam.permissions_boundary_arn, null)
  tags                     = local.tags

  depends_on = [terraform_data.rules]
}

module "ec2" {
  count  = local.ec2_on ? 1 : 0
  source = "../modules/ec2"

  name           = local.name
  instance_count = try(local.cfg.ec2.count, 1)
  instance_type  = try(local.cfg.ec2.instance_type, "t3.micro")
  ami_id         = try(local.cfg.ec2.ami_id, null)
  vpc_id         = local.vpc_id
  subnet_ids     = local.ec2_subnet_ids
  public         = local.ec2_public
  root_volume_gb = try(local.cfg.ec2.root_volume_gb, 20)
  ingress_ports  = try(local.cfg.ec2.ingress_ports, [])
  ingress_cidrs  = try(local.cfg.ec2.ingress_cidrs, [])
  tags           = local.tags

  depends_on = [terraform_data.rules]
}

module "eks" {
  count  = local.eks_on ? 1 : 0
  source = "../modules/eks"

  name                         = local.eks_name
  kubernetes_version           = local.cfg.eks.version
  vpc_id                       = local.vpc_id
  subnet_ids                   = local.private_subnet_ids
  endpoint_public_access       = try(local.cfg.eks.public_endpoint, false)
  endpoint_public_access_cidrs = try(local.cfg.eks.public_endpoint_cidrs, ["0.0.0.0/0"])
  node_groups                  = try(local.cfg.eks.node_groups, {})
  extra_addons                 = try(local.cfg.eks.extra_addons, {})
  tags                         = local.tags

  depends_on = [terraform_data.rules]
}

module "route53" {
  count  = local.route53_on ? 1 : 0
  source = "../modules/route53"

  zone_name    = local.cfg.route53.zone_name
  private_zone = try(local.cfg.route53.private, true)
  vpc_id       = local.vpc_id
  records      = try(local.cfg.route53.records, {})
  tags         = local.tags

  depends_on = [terraform_data.rules]
}

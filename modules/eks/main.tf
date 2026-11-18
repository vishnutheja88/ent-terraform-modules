############################################################
# Wrapper: EKS on top of terraform-aws-modules/eks (v21)
# Dependencies pulled in by upstream: KMS (vendored ../terraform-aws-kms),
# tls + time providers, node-group submodules.
############################################################

locals {
  node_groups = {
    for k, ng in var.node_groups : k => {
      instance_types = try(ng.instance_types, ["t3.large"])
      capacity_type  = try(ng.capacity_type, "ON_DEMAND")
      ami_type       = try(ng.ami_type, "AL2023_x86_64_STANDARD")
      min_size       = try(ng.min_size, 1)
      max_size       = try(ng.max_size, 3)
      desired_size   = try(ng.desired_size, 2)
      disk_size      = try(ng.disk_size, 50)
      labels         = try(ng.labels, {})
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  # Org-standard add-ons; vpc-cni + pod identity before nodes join
  default_addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }
}

module "this" {
  source = "../../upstream/terraform-aws-eks"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  endpoint_private_access      = true

  enable_cluster_creator_admin_permissions = true
  access_entries                           = var.access_entries

  # Encryption of secrets with a module-managed KMS key (vendored KMS module)
  create_kms_key = true

  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 30

  addons                  = merge(local.default_addons, var.extra_addons)
  eks_managed_node_groups = local.node_groups

  tags = var.tags
}

################################################################################
# stack-wrapper/main.tf  -  Master Wrapper Root Module
#
# Stage 1 copies this folder (plus ../modules and ../upstream) into /workspace
# together with the team's values.yaml. Stages 2/3 run plan/apply here.
#
#   values.yaml toggle        module (count = 0 or 1)
#   networking.enabled   ->   modules/networking   (VPC, 3 tiers)
#   tls.enabled          ->   modules/acm-private-cert (RAM-shared Subordinate CA)
#   ecs.enabled          ->   modules/ecs          (Fargate + ALB, HTTPS if tls)
#   rds.enabled          ->   modules/rds          (private, encrypted)
################################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  cfg = yamldecode(file(var.values_file))

  team = local.cfg.team
  env  = local.cfg.environment
  app  = local.cfg.app_name
  name = "${local.team}-${local.env}-${local.app}"

  networking_on = try(local.cfg.networking.enabled, false)
  tls_on        = try(local.cfg.tls.enabled, false)
  ecs_on        = try(local.cfg.ecs.enabled, false)
  rds_on        = try(local.cfg.rds.enabled, false)

  # Boundary created by account onboarding in every spoke. Account id is read
  # from the live credentials, never hardcoded.
  permissions_boundary_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.permissions_boundary_name}"

  # Platform tags win over team tags so ownership/audit tags cannot be spoofed.
  tags = merge(
    try(local.cfg.tags, {}),
    {
      Team            = local.team
      Environment     = local.env
      Application     = local.app
      PlatformVersion = var.platform_version
      SourceRepo      = var.source_repo
      SourceCommit    = substr(var.source_commit, 0, 12)
      ManagedBy       = "platform-terraform"
    }
  )
}

# ---------------------------------------------------------------- Cross-checks
# Values that come from two places must agree, or the plan stops.
resource "terraform_data" "guardrails" {
  input = {
    environment      = local.env
    platform_version = var.platform_version
  }

  lifecycle {
    precondition {
      condition     = local.env == var.environment
      error_message = "values.yaml says environment '${local.env}' but it lives in the '${var.environment}/' folder."
    }
    precondition {
      condition     = local.cfg.platform_version == var.platform_version
      error_message = "values.yaml asks for platform_version ${local.cfg.platform_version} but the pipeline assembled ${var.platform_version}."
    }
    precondition {
      condition     = !local.tls_on || var.subordinate_ca_arn != null
      error_message = "tls.enabled is true but no Subordinate CA ARN was injected (SSM /platform/pki/subordinate-ca-arn)."
    }
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.target_account_id
      error_message = "Credentials are for account ${data.aws_caller_identity.current.account_id}, expected ${var.target_account_id}."
    }
  }
}

# ---------------------------------------------------------------- Networking
module "networking" {
  count  = local.networking_on ? 1 : 0
  source = "../modules/networking"

  name                     = local.name
  vpc_cidr                 = local.cfg.networking.vpc_cidr
  az_count                 = try(local.cfg.networking.az_count, 2)
  nat_gateway              = try(local.cfg.networking.nat_gateway, "single")
  enable_flow_log          = true
  permissions_boundary_arn = local.permissions_boundary_arn
  tags                     = local.tags

  depends_on = [terraform_data.guardrails]
}

# ---------------------------------------------------------------- Private TLS certificate
module "tls" {
  count  = local.tls_on ? 1 : 0
  source = "../modules/acm-private-cert"

  domain_name               = local.cfg.tls.domain_name
  subject_alternative_names = try(local.cfg.tls.subject_alternative_names, [])
  certificate_authority_arn = var.subordinate_ca_arn
  tags                      = local.tags

  depends_on = [terraform_data.guardrails]
}

# ---------------------------------------------------------------- ECS
module "ecs" {
  count  = local.ecs_on ? 1 : 0
  source = "../modules/ecs"

  name               = local.name
  vpc_id             = module.networking[0].vpc_id
  private_subnet_ids = module.networking[0].private_subnet_ids
  public_subnet_ids  = module.networking[0].public_subnet_ids

  services          = local.cfg.ecs.services
  alb_internal      = try(local.cfg.ecs.alb_internal, true)
  alb_ingress_cidrs = try(local.cfg.ecs.alb_ingress_cidrs, [local.cfg.networking.vpc_cidr])
  certificate_arn   = local.tls_on ? module.tls[0].certificate_arn : null

  permissions_boundary_arn = local.permissions_boundary_arn
  tags                     = local.tags
}

# ---------------------------------------------------------------- RDS
module "rds" {
  count  = local.rds_on ? 1 : 0
  source = "../modules/rds"

  name        = local.name
  environment = local.env

  engine                = local.cfg.rds.engine
  engine_version        = tostring(local.cfg.rds.engine_version)
  instance_class        = local.cfg.rds.instance_class
  allocated_storage     = local.cfg.rds.allocated_storage
  max_allocated_storage = try(local.cfg.rds.max_allocated_storage, local.cfg.rds.allocated_storage)
  multi_az              = try(local.cfg.rds.multi_az, false)
  db_name               = local.cfg.rds.db_name

  vpc_id                     = module.networking[0].vpc_id
  db_subnet_group_name       = module.networking[0].database_subnet_group_name
  allowed_security_group_ids = local.ecs_on ? [module.ecs[0].task_security_group_id] : []

  tags = local.tags
}

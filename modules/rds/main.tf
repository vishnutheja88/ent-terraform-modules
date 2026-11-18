################################################################################
# modules/rds
# Platform-standard RDS instance on top of the vendored terraform-aws-modules/rds.
# Enforced: encrypted storage, private only, master password in Secrets Manager
# (never in state or values files), deletion protection + final snapshot in prod.
################################################################################

locals {
  major = var.engine == "postgres" ? split(".", var.engine_version)[0] : join(".", slice(split(".", var.engine_version), 0, 2))

  # Parameter group family / option group major version, derived from the engine.
  family = "${var.engine}${local.major}"
  port   = var.engine == "postgres" ? 5432 : 3306

  is_prod = var.environment == "prod"
}

# Only the callers listed in allowed_security_group_ids (ECS tasks) may connect.
resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "RDS ${var.name}: inbound ${local.port} from app tiers only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds" })
}

# count (not for_each): SG ids are unknown until apply, but the list length is known at plan.
resource "aws_vpc_security_group_ingress_rule" "from_apps" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  description                  = "DB access from app tier ${count.index + 1}"
}

module "db" {
  source = "../../upstream/terraform-aws-rds"

  identifier = var.name

  engine               = var.engine
  engine_version       = var.engine_version
  family               = local.family
  major_engine_version = local.major
  instance_class       = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                     = var.db_name
  username                    = var.username
  port                        = local.port
  manage_master_user_password = true # password lives in Secrets Manager

  # Networking: subnet group comes from modules/networking
  create_db_subnet_group = false
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Environment-driven safety settings
  deletion_protection     = local.is_prod
  skip_final_snapshot     = !local.is_prod
  backup_retention_period = local.is_prod ? 14 : 1
  copy_tags_to_snapshot   = true

  create_db_option_group = var.engine == "mysql"

  # No IAM role is created here (monitoring off) -> nothing for the boundary to cover.
  create_monitoring_role = false
  monitoring_interval    = 0

  performance_insights_enabled = local.is_prod
  auto_minor_version_upgrade   = true
  apply_immediately            = !local.is_prod

  tags = var.tags
}

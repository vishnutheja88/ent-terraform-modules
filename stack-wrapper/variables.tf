################################################################################
# stack-wrapper/variables.tf
#
# values_file  - the ONLY team input (their values.yaml, copied into /workspace)
# everything else is injected by the pipeline (TF_VAR_*), never by teams:
#   target_account_id, environment, platform_version  <- DynamoDB registry + path
#   subordinate_ca_arn                                <- SSM in Shared Services
#   aws_profile                                       <- "spoke" (assumed-role creds)
#
# Every rule below runs at `terraform plan`, BEFORE anything is created, so a
# bad values.yaml fails fast with a message the app team can act on.
# NOTE: conditions re-read the file instead of using a local on purpose:
# a validation that depends on a local derived from the same variable can cycle.
################################################################################

variable "values_file" {
  description = "Path to the team's values.yaml inside the assembled workspace"
  type        = string

  # ---------- File shape ----------
  validation {
    condition     = can(yamldecode(file(var.values_file)))
    error_message = "values.yaml is not valid YAML."
  }

  validation {
    condition = try(alltrue([
      for k in keys(yamldecode(file(var.values_file))) :
      contains(["platform_version", "team", "environment", "app_name", "region", "tags", "networking", "ecs", "rds", "tls"], k)
    ]), false)
    error_message = "Unknown top-level key in values.yaml. Allowed: platform_version, team, environment, app_name, region, tags, networking, ecs, rds, tls."
  }

  validation {
    condition = alltrue([
      for k in ["platform_version", "team", "environment", "app_name", "region"] :
      can(yamldecode(file(var.values_file))[k])
    ])
    error_message = "values.yaml must set platform_version, team, environment, app_name and region."
  }

  # ---------- Identity & naming ----------
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", try(yamldecode(file(var.values_file)).platform_version, "")))
    error_message = "platform_version must be an immutable release tag like \"v1.2.0\" (no branches, no \"latest\")."
  }

  validation {
    condition     = contains(["dev", "staging", "prod"], try(yamldecode(file(var.values_file)).environment, ""))
    error_message = "environment must be dev, staging or prod."
  }

  validation {
    condition = alltrue([
      for k in ["team", "app_name"] :
      can(regex("^[a-z][a-z0-9-]{1,19}$", try(yamldecode(file(var.values_file))[k], "")))
    ])
    error_message = "team and app_name must be 2-20 chars: lowercase letters, digits, hyphens, starting with a letter."
  }

  validation {
    condition     = can(regex("^(us|eu|ap|ca|sa|me|af|il|mx)(-gov)?-[a-z]+-[0-9]$", try(yamldecode(file(var.values_file)).region, "")))
    error_message = "region must be an AWS region code such as us-east-1."
  }

  # ---------- Networking ----------
  validation {
    # Terraform's && does not short-circuit, so the whole check sits inside try().
    condition = !try(yamldecode(file(var.values_file)).networking.enabled, false) || try(
      can(cidrnetmask(yamldecode(file(var.values_file)).networking.vpc_cidr)) &&
      tonumber(split("/", yamldecode(file(var.values_file)).networking.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", yamldecode(file(var.values_file)).networking.vpc_cidr)[1]) <= 20 &&
      can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", yamldecode(file(var.values_file)).networking.vpc_cidr)),
      false
    )
    error_message = "networking.vpc_cidr must be a private (RFC 1918) CIDR between /16 and /20, e.g. 10.40.0.0/16."
  }

  validation {
    condition     = contains(["none", "single", "per_az"], try(yamldecode(file(var.values_file)).networking.nat_gateway, "single"))
    error_message = "networking.nat_gateway must be none, single or per_az."
  }

  validation {
    condition     = contains([2, 3], try(yamldecode(file(var.values_file)).networking.az_count, 2))
    error_message = "networking.az_count must be 2 or 3."
  }

  validation {
    condition = !(
      (try(yamldecode(file(var.values_file)).ecs.enabled, false) || try(yamldecode(file(var.values_file)).rds.enabled, false)) &&
      !try(yamldecode(file(var.values_file)).networking.enabled, false)
    )
    error_message = "ecs and rds need networking.enabled: true (the stack builds its own VPC)."
  }

  # ---------- ECS ----------
  validation {
    condition = alltrue([
      for s in values(try(yamldecode(file(var.values_file)).ecs.services, {})) :
      try(contains([256, 512, 1024, 2048, 4096], s.cpu) && (
        (s.cpu == 256 && contains([512, 1024, 2048], s.memory)) ||
        (s.cpu >= 512 && s.memory % 1024 == 0 && s.memory >= s.cpu * 2 && s.memory <= min(s.cpu * 8, 30720))
      ), false)
    ])
    error_message = "ecs.services.*: cpu/memory must be a valid Fargate size (e.g. 256/512, 512/1024, 1024/2048 ... 4096/30720)."
  }

  validation {
    condition = alltrue([
      for s in values(try(yamldecode(file(var.values_file)).ecs.services, {})) :
      try(s.container_port, 0) >= 1024 && try(s.container_port, 0) <= 65535 &&
      try(s.desired_count, -1) >= 0 && try(s.desired_count, -1) <= 20
    ])
    error_message = "ecs.services.*: container_port must be 1024-65535 and desired_count 0-20."
  }

  validation {
    condition = alltrue([
      for s in values(try(yamldecode(file(var.values_file)).ecs.services, {})) :
      can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(@sha256:[0-9a-f]{64}|:[A-Za-z0-9._-]{1,128})$", try(s.image, ""))) &&
      !endswith(try(s.image, ""), ":latest")
    ])
    error_message = "ecs.services.*.image must be a full registry/repo reference pinned to a tag or digest; \":latest\" is not allowed."
  }

  validation {
    condition = alltrue([
      for c in try(yamldecode(file(var.values_file)).ecs.alb_ingress_cidrs, []) :
      can(cidrnetmask(c)) && c != "0.0.0.0/0"
    ])
    error_message = "ecs.alb_ingress_cidrs must be valid CIDRs and cannot be 0.0.0.0/0."
  }

  # ---------- RDS ----------
  validation {
    condition = !try(yamldecode(file(var.values_file)).rds.enabled, false) || (
      contains(["postgres", "mysql"], try(yamldecode(file(var.values_file)).rds.engine, "")) &&
      contains(["db.t4g.micro", "db.t4g.small", "db.t4g.medium", "db.m7g.large", "db.m7g.xlarge", "db.r7g.large", "db.r7g.xlarge"], try(yamldecode(file(var.values_file)).rds.instance_class, ""))
    )
    error_message = "rds.engine must be postgres or mysql, and rds.instance_class one of db.t4g.micro|small|medium, db.m7g.large|xlarge, db.r7g.large|xlarge."
  }

  validation {
    condition = !try(yamldecode(file(var.values_file)).rds.enabled, false) || (
      try(yamldecode(file(var.values_file)).rds.allocated_storage, 0) >= 20 &&
      try(yamldecode(file(var.values_file)).rds.allocated_storage, 0) <= 1000 &&
      try(yamldecode(file(var.values_file)).rds.max_allocated_storage, try(yamldecode(file(var.values_file)).rds.allocated_storage, 0)) >= try(yamldecode(file(var.values_file)).rds.allocated_storage, 0) &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", try(yamldecode(file(var.values_file)).rds.db_name, "")))
    )
    error_message = "rds: allocated_storage 20-1000 GiB, max_allocated_storage >= allocated_storage, db_name letters/digits/underscore starting with a letter."
  }

  # ---------- TLS ----------
  validation {
    condition = !try(yamldecode(file(var.values_file)).tls.enabled, false) || alltrue([
      for d in concat([try(yamldecode(file(var.values_file)).tls.domain_name, "")], try(yamldecode(file(var.values_file)).tls.subject_alternative_names, [])) :
      can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))
    ])
    error_message = "tls.domain_name and subject_alternative_names must be lowercase DNS names."
  }

  # ---------- Production guardrails ----------
  validation {
    condition = try(yamldecode(file(var.values_file)).environment, "") != "prod" || (
      (!try(yamldecode(file(var.values_file)).rds.enabled, false) || try(yamldecode(file(var.values_file)).rds.multi_az, false)) &&
      alltrue([for s in values(try(yamldecode(file(var.values_file)).ecs.services, {})) : try(s.desired_count, 0) >= 2]) &&
      try(yamldecode(file(var.values_file)).networking.nat_gateway, "single") != "none"
    )
    error_message = "prod requires rds.multi_az: true, desired_count >= 2 for every ECS service, and a NAT gateway."
  }
}

# ------------------------------------------------------------------ Injected by the pipeline

variable "target_account_id" {
  description = "Spoke account from the DynamoDB registry; the provider refuses any other account"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "target_account_id must be a 12-digit AWS account id."
  }
}

variable "environment" {
  description = "Environment derived from the changed path (dev/ staging/ prod/); must match values.yaml"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "platform_version" {
  description = "Tag of platform-terraform-modules that Stage 1 cloned; must match values.yaml"
  type        = string
}

variable "subordinate_ca_arn" {
  description = "RAM-shared Subordinate CA ARN (from SSM /platform/pki/subordinate-ca-arn). Never the Root CA."
  type        = string
  default     = null

  validation {
    condition     = var.subordinate_ca_arn == null || can(regex("^arn:aws[a-z-]*:acm-pca:[a-z0-9-]+:[0-9]{12}:certificate-authority/[0-9a-f-]{36}$", var.subordinate_ca_arn))
    error_message = "subordinate_ca_arn must be an ACM PCA certificate-authority ARN."
  }
}

variable "aws_profile" {
  description = "Named profile holding the assumed spoke-role credentials (set by the buildspec); null = default chain"
  type        = string
  default     = null
}

variable "permissions_boundary_name" {
  description = "Boundary policy created in every spoke by account onboarding"
  type        = string
  default     = "PlatformWorkloadBoundary"
}

variable "source_repo" {
  description = "Team repository (for tags/audit)"
  type        = string
  default     = "unknown"
}

variable "source_commit" {
  description = "Commit SHA that triggered the run (for tags/audit)"
  type        = string
  default     = "unknown"
}

variable "name" {
  description = "Name prefix, e.g. payments-dev-checkout (ALB name uses the first 32 chars)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  description = "Only used when alb_internal = false"
  type        = list(string)
  default     = []
}

variable "services" {
  description = "One Fargate service per key"
  type = map(object({
    image             = string
    cpu               = number
    memory            = number
    desired_count     = number
    container_port    = number
    health_check_path = optional(string, "/health")
    path_pattern      = optional(string, "/*")
    cpu_architecture  = optional(string, "X86_64")
    environment       = optional(map(string), {})
    secrets           = optional(map(string), {}) # ENV_NAME => Secrets Manager ARN
  }))

  validation {
    condition     = length(var.services) <= 10
    error_message = "At most 10 services per stack."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : contains([256, 512, 1024, 2048, 4096], s.cpu)])
    error_message = "cpu must be one of 256, 512, 1024, 2048, 4096 (Fargate sizes)."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : contains(["X86_64", "ARM64"], s.cpu_architecture)])
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "alb_internal" {
  description = "Internal ALB (default). Private-CA certs are only trusted inside the org."
  type        = bool
  default     = true
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB listener(s)"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS; null = HTTP only"
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}

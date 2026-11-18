variable "name" {
  description = "Name prefix, e.g. payments-dev-checkout"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (/16 to /20). Validated again in stack-wrapper."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR between /16 and /20."
  }
}

variable "az_count" {
  type    = number
  default = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway" {
  description = "none | single | per_az"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway)
    error_message = "nat_gateway must be none, single or per_az."
  }
}

variable "enable_flow_log" {
  type    = bool
  default = true
}

variable "permissions_boundary_arn" {
  description = "Boundary attached to the flow-log IAM role (spoke deploy role requires one on every role it creates)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

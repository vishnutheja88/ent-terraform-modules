variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Managed by ent-terraform-modules"
}

variable "trusted_services" {
  description = "AWS services allowed to assume the role, e.g. [\"ec2.amazonaws.com\"]"
  type        = list(string)
  default     = []
}

variable "trusted_role_arns" {
  description = "IAM role/account ARNs allowed to assume the role"
  type        = list(string)
  default     = []
}

variable "policy_arns" {
  description = "Managed policies to attach, { name = arn }"
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "Org permissions boundary (recommended in enterprise accounts)"
  type        = string
  default     = null
}

variable "max_session_duration" {
  type    = number
  default = 3600
}

variable "create_instance_profile" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

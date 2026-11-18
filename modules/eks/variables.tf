variable "name" {
  type = string
}

variable "kubernetes_version" {
  description = "e.g. \"1.34\""
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for nodes and control-plane ENIs"
  type        = list(string)
}

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = <<-EOT
    Simplified managed node groups, e.g.
    { general = { instance_types = ["t3.large"], min_size = 1, max_size = 3, desired_size = 2 } }
  EOT
  type        = any
  default     = {}
}

variable "extra_addons" {
  description = "Extra EKS add-ons merged with org defaults, e.g. { aws-ebs-csi-driver = {} }"
  type        = any
  default     = {}
}

variable "access_entries" {
  description = "Extra cluster access entries (upstream format)"
  type        = any
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "name" {
  description = "Name prefix"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR (/16 recommended)"
  type        = string
}

variable "az_count" {
  description = "Number of AZs"
  type        = number
  default     = 2
}

variable "create_igw" {
  description = "Create an Internet Gateway and public subnets"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "NAT for private subnets (required for EKS nodes without VPC endpoints)"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "One shared NAT (cheaper) instead of one per AZ (HA)"
  type        = bool
  default     = true
}

variable "enable_flow_log" {
  description = "VPC flow logs to CloudWatch"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "If set, subnets get kubernetes.io/cluster/<name> discovery tags"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

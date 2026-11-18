variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Managed by ent-terraform-modules"
}

variable "vpc_id" {
  type = string
}

variable "ingress_ports" {
  description = "TCP ports to open"
  type        = list(number)
  default     = []
}

variable "ingress_cidrs" {
  description = "IPv4 CIDRs allowed on every ingress port"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

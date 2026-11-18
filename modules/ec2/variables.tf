variable "name" {
  type = string
}

variable "instance_count" {
  type    = number
  default = 1
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_id" {
  description = "Optional AMI; null = latest Amazon Linux 2023"
  type        = string
  default     = null
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Instances spread round-robin across these subnets"
  type        = list(string)
}

variable "public" {
  description = "Assign public IPs (subnets must be public)"
  type        = bool
  default     = false
}

variable "root_volume_gb" {
  type    = number
  default = 20
}

variable "ingress_ports" {
  type    = list(number)
  default = []
}

variable "ingress_cidrs" {
  type    = list(string)
  default = []
}

variable "extra_policy_arns" {
  description = "Extra managed policies for the instance role, { name = arn }"
  type        = map(string)
  default     = {}
}

variable "user_data" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

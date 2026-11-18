variable "name" {
  description = "DB identifier, e.g. payments-dev-checkout"
  type        = string
}

variable "environment" {
  description = "dev | staging | prod (drives deletion protection, backups, snapshots)"
  type        = string
}

variable "engine" {
  type = string

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be postgres or mysql."
  }
}

variable "engine_version" {
  description = "e.g. \"16\" or \"16.4\" for postgres, \"8.0\" for mysql"
  type        = string
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling (GiB)"
  type        = number
}

variable "multi_az" {
  type = bool
}

variable "db_name" {
  type = string
}

variable "username" {
  type    = string
  default = "app_admin"
}

variable "kms_key_arn" {
  description = "Optional customer-managed key; null = AWS-managed RDS key (still encrypted)"
  type        = string
  default     = null
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_group_name" {
  type = string
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect (e.g. ECS task SGs)"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

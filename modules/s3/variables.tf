variable "name" {
  description = "Globally unique bucket name"
  type        = string
}

variable "versioning" {
  type    = bool
  default = true
}

variable "expire_days" {
  description = "Delete objects (and old versions) after N days; null = keep forever"
  type        = number
  default     = null
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key; null = S3-managed AES256"
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a non-empty bucket (dev only)"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "name" {
  description = "IAM role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider"
  type        = string
}

variable "namespace" {
  type = string
}

variable "service_account" {
  type = string
}

variable "bucket_arns" {
  description = "Buckets this service account may use"
  type        = list(string)
}

variable "read_only" {
  type    = bool
  default = false
}

variable "kms_key_arn" {
  description = "KMS key used by the bucket, if any"
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

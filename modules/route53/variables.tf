variable "zone_name" {
  description = "e.g. dev.example.internal"
  type        = string
}

variable "private_zone" {
  type    = bool
  default = true
}

variable "vpc_id" {
  description = "Required when private_zone = true"
  type        = string
  default     = null
}

variable "records" {
  description = <<-EOT
    Map of records keyed by subdomain, e.g.
    { app = { type = "A", records = ["10.20.128.10"] } }
    or an alias: { www = { type = "A", alias = { name = "...", zone_id = "..." } } }
  EOT
  type        = any
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

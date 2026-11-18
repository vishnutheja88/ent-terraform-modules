output "name" {
  value = module.this.s3_bucket_id
}

output "arn" {
  value = module.this.s3_bucket_arn
}

output "regional_domain_name" {
  value = module.this.s3_bucket_bucket_regional_domain_name
}

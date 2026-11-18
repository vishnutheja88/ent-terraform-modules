output "certificate_arn" {
  value = aws_acm_certificate.this.arn
}

output "domain_name" {
  value = aws_acm_certificate.this.domain_name
}

output "not_after" {
  description = "Expiry timestamp (ACM renews automatically)"
  value       = aws_acm_certificate.this.not_after
}

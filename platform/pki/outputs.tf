output "subordinate_ca_arn" {
  description = "Give this to platform/shared-services (var.subordinate_ca_arn); it is published to SSM for pipelines"
  value       = aws_acmpca_certificate_authority.subordinate.arn
}

output "root_ca_arn" {
  description = "For audit only. Never share or inject into workloads."
  value       = aws_acmpca_certificate_authority.root.arn
}

output "root_certificate_pem" {
  description = "Distribute to client trust stores so they trust certs issued by the Subordinate CA"
  value       = aws_acmpca_certificate.root.certificate
}

output "ram_resource_share_arn" {
  value = aws_ram_resource_share.subordinate_ca.arn
}

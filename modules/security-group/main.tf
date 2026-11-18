############################################################
# Wrapper: security group on top of terraform-aws-modules/security-group
# values.yaml gives ports + CIDRs; we build upstream's rule maps.
############################################################

locals {
  ingress_rules = merge([
    for port in var.ingress_ports : {
      for cidr in var.ingress_cidrs :
      "tcp-${port}-${replace(replace(cidr, ".", "-"), "/", "_")}" => {
        from_port   = port
        to_port     = port
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
        description = "tcp/${port} from ${cidr}"
      }
    }
  ]...)
}

module "this" {
  source = "../../upstream/terraform-aws-security-group"

  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  ingress_rules = local.ingress_rules
  egress_rules = {
    all-ipv4 = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "All outbound IPv4"
    }
  }

  tags = var.tags
}

############################################################
# Wrapper: hosted zone + records on top of terraform-aws-modules/route53
############################################################

module "this" {
  source = "../../upstream/terraform-aws-route53"

  name         = var.zone_name
  comment      = "Managed by ent-terraform-modules"
  private_zone = var.private_zone

  vpc = var.private_zone ? {
    primary = { vpc_id = var.vpc_id }
  } : null

  records = {
    for k, r in var.records : k => {
      type    = r.type
      ttl     = try(r.ttl, 300)
      records = try(r.records, null)
      alias = try(r.alias, null) == null ? null : {
        name                   = r.alias.name
        zone_id                = r.alias.zone_id
        evaluate_target_health = try(r.alias.evaluate_target_health, false)
      }
    }
  }

  tags = var.tags
}

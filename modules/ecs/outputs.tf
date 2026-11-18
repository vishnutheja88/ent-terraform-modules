output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "listener_protocol" {
  value = local.tls ? "HTTPS" : "HTTP"
}

output "task_security_group_id" {
  description = "Allow this SG into databases (stack-wrapper wires it into modules/rds)"
  value       = aws_security_group.tasks.id
}

output "service_names" {
  value = [for s in aws_ecs_service.svc : s.name]
}

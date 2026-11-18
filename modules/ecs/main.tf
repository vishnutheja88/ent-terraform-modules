################################################################################
# modules/ecs
# ECS Fargate cluster + one service per entry in var.services, behind one ALB.
# - Tasks run in private subnets, no public IPs.
# - ALB is internal by default; HTTPS with the private cert when TLS is on.
# - Every IAM role gets the spoke's permissions boundary.
################################################################################

data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  service_keys = sort(keys(var.services))
  tls          = var.certificate_arn != null

  alb_subnets = var.alb_internal ? var.private_subnet_ids : var.public_subnet_ids

  # Ports the ALB listens on: 443 (+80 redirect) with TLS, otherwise 80.
  alb_ports = local.tls ? toset(["80", "443"]) : toset(["80"])

  listener_arn = local.tls ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn

  services_with_secrets = { for k, s in var.services : k => s if length(s.secrets) > 0 }
}

# ---------------------------------------------------------------- Cluster
resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each = var.services

  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------- IAM (boundary on every role)
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Used by the ECS agent: pull images, write logs, read secrets.
resource "aws_iam_role" "execution" {
  name                 = "${var.name}-ecs-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  count = length(local.services_with_secrets) > 0 ? 1 : 0

  statement {
    sid       = "ReadInjectedSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = distinct(flatten([for s in values(local.services_with_secrets) : values(s.secrets)]))
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = length(local.services_with_secrets) > 0 ? 1 : 0

  name   = "read-injected-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

# Used by the application code. Empty by default: teams cannot grant themselves
# permissions from a values file; extra access is a platform module change.
resource "aws_iam_role" "task" {
  for_each = var.services

  name                 = "${var.name}-${each.key}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

# ---------------------------------------------------------------- Security groups
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = { for pair in setproduct(local.alb_ports, var.alb_ingress_cidrs) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value[0])
  to_port           = tonumber(each.value[0])
  cidr_ipv4         = each.value[1]
  description       = "tcp/${each.value[0]} from ${each.value[1]}"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  for_each = var.services

  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  description                  = "to ${each.key} tasks"
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "ECS tasks ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-tasks" })
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  for_each = var.services

  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  description                  = "${each.key} from ALB"
}

# Tasks need outbound HTTPS for ECR, Secrets Manager, CloudWatch Logs (via NAT or endpoints).
resource "aws_vpc_security_group_egress_rule" "tasks_out" {
  security_group_id = aws_security_group.tasks.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Outbound (ECR, AWS APIs, database)"
}

# ---------------------------------------------------------------- Load balancer
resource "aws_lb" "this" {
  name                       = trimsuffix(substr(var.name, 0, 32), "-")
  internal                   = var.alb_internal
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = local.alb_subnets
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_listener" "https" {
  count = local.tls ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # With TLS: redirect everything to HTTPS. Without: serve 404 by default.
  dynamic "default_action" {
    for_each = local.tls ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.tls ? [] : [1]
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not found"
        status_code  = "404"
      }
    }
  }
}

resource "aws_lb_target_group" "svc" {
  for_each = var.services

  port                 = each.value.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "svc" {
  for_each = var.services

  listener_arn = local.listener_arn
  priority     = 100 + index(local.service_keys, each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }
}

# ---------------------------------------------------------------- Tasks and services
resource "aws_ecs_task_definition" "svc" {
  for_each = var.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = each.value.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true
      portMappings = [
        { containerPort = each.value.container_port, protocol = "tcp" }
      ]
      environment = [for k, v in each.value.environment : { name = k, value = v }]
      secrets     = [for k, v in each.value.secrets : { name = k, valueFrom = v }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.svc[each.key].name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = each.key
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "svc" {
  for_each = var.services

  name                              = each.key
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.svc[each.key].arn
  desired_count                     = each.value.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 60
  propagate_tags                    = "SERVICE"
  enable_ecs_managed_tags           = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.svc[each.key].arn
    container_name   = each.key
    container_port   = each.value.container_port
  }

  # A bad image or failing health check rolls back automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = var.tags

  depends_on = [aws_lb_listener_rule.svc]
}

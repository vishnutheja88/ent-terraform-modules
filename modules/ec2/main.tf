############################################################
# Wrapper: N EC2 instances on top of terraform-aws-modules/ec2-instance
# - one shared SG (via our security-group wrapper)
# - one IAM instance profile with SSM (no SSH keys needed)
# - IMDSv2, encrypted root volume enforced
############################################################

module "sg" {
  source = "../security-group"

  name          = "${var.name}-ec2"
  vpc_id        = var.vpc_id
  ingress_ports = var.ingress_ports
  ingress_cidrs = var.ingress_cidrs
  tags          = var.tags
}

module "instance" {
  source   = "../../upstream/terraform-aws-ec2-instance"
  for_each = { for i in range(var.instance_count) : format("%02d", i + 1) => i }

  name          = "${var.name}-ec2-${each.key}"
  instance_type = var.instance_type
  ami           = var.ami_id # null -> upstream default: latest AL2023 via SSM
  subnet_id     = var.subnet_ids[each.value % length(var.subnet_ids)]

  associate_public_ip_address = var.public
  create_security_group       = false
  vpc_security_group_ids      = [module.sg.id]

  create_iam_instance_profile = true
  iam_role_name               = "${var.name}-ec2-${each.key}"
  iam_role_policies = merge(
    { ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" },
    var.extra_policy_arns
  )

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device = {
    encrypted = true
    type      = "gp3"
    size      = var.root_volume_gb
  }

  user_data = var.user_data
  tags      = var.tags
}

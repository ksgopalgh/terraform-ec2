provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "existing" {
  count = var.use_existing_network ? 1 : 0
  id    = var.existing_vpc_id
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Legacy state migration guards:
# these auto-map older single-instance addresses to the multi-instance windows01 key.
moved {
  from = aws_instance.windows
  to   = aws_instance.windows["windows01"]
}

moved {
  from = aws_security_group.instance[0]
  to   = aws_security_group.instance["windows01"]
}

moved {
  from = aws_eip_association.windows[0]
  to   = aws_eip_association.windows["windows01"]
}

moved {
  from = aws_eip.windows[0]
  to   = aws_eip.windows["windows01"]
}

locals {
  az = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]

  base_tags = merge(
    {
      ManagedBy   = "Terraform"
      Project     = "Windows-Playwright-Automation"
      Environment = "test"
    },
    var.tags
  )

  endpoint_services = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id        = var.use_existing_network ? data.aws_vpc.existing[0].id : aws_vpc.this[0].id
  subnet_id     = var.use_existing_network ? var.existing_subnet_id : aws_subnet.public[0].id
  vpc_cidr      = var.use_existing_network ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
  vpc_ipv6_cidr = var.use_existing_network ? coalesce(var.existing_vpc_ipv6_cidr, try(data.aws_vpc.existing[0].ipv6_cidr_block, null)) : aws_vpc.this[0].ipv6_cidr_block

  default_key_pair_name              = var.key_pair_name == null ? "" : trimspace(var.key_pair_name)
  default_existing_eip_allocation_id = var.existing_eip_allocation_id == null ? "" : trimspace(var.existing_eip_allocation_id)
  default_access_mode                = lower(var.access_mode)
  default_create_key_pair            = var.create_key_pair
  default_allow_eip_reassociation    = var.allow_eip_reassociation

  instance_defaults = {
    instance_type               = var.instance_type
    subnet_id                   = local.subnet_id
    root_volume_size            = var.root_volume_size
    key_pair_name               = local.default_key_pair_name != "" ? local.default_key_pair_name : null
    create_key_pair             = local.default_create_key_pair
    access_mode                 = local.default_access_mode
    create_eip                  = var.create_eip
    existing_eip_allocation_id  = local.default_existing_eip_allocation_id != "" ? local.default_existing_eip_allocation_id : null
    allow_eip_reassociation     = local.default_allow_eip_reassociation
    assign_ipv6_address_count   = 1
    existing_security_group_ids = var.existing_security_group_ids
    enable_rdp                  = var.enable_rdp
    rdp_allowed_cidrs           = var.rdp_allowed_cidrs
    rdp_allowed_ipv6_cidrs      = var.rdp_allowed_ipv6_cidrs
    tags                        = {}
  }

  instances_requested = {
    for instance_key, cfg in var.instances : instance_key => {
      instance_type               = coalesce(try(cfg.instance_type, null), local.instance_defaults.instance_type)
      subnet_id                   = coalesce(try(cfg.subnet_id, null), local.instance_defaults.subnet_id)
      root_volume_size            = coalesce(try(cfg.root_volume_size, null), local.instance_defaults.root_volume_size)
      create_key_pair             = coalesce(try(cfg.create_key_pair, null), local.instance_defaults.create_key_pair)
      key_pair_name               = try(trimspace(cfg.key_pair_name), "") != "" ? trimspace(cfg.key_pair_name) : (coalesce(try(cfg.create_key_pair, null), local.instance_defaults.create_key_pair) ? "${var.name_prefix}-${instance_key}-kp" : local.instance_defaults.key_pair_name)
      access_mode                 = lower(coalesce(try(cfg.access_mode, null), local.instance_defaults.access_mode))
      create_eip                  = coalesce(try(cfg.create_eip, null), local.instance_defaults.create_eip)
      existing_eip_allocation_id  = try(trimspace(cfg.existing_eip_allocation_id), "") != "" ? trimspace(cfg.existing_eip_allocation_id) : local.instance_defaults.existing_eip_allocation_id
      allow_eip_reassociation     = coalesce(try(cfg.allow_eip_reassociation, null), local.instance_defaults.allow_eip_reassociation)
      assign_ipv6_address_count   = coalesce(try(cfg.assign_ipv6_address_count, null), local.instance_defaults.assign_ipv6_address_count)
      existing_security_group_ids = coalesce(try(cfg.existing_security_group_ids, null), local.instance_defaults.existing_security_group_ids)
      rdp_allowed_cidrs           = coalesce(try(cfg.rdp_allowed_cidrs, null), local.instance_defaults.rdp_allowed_cidrs)
      rdp_allowed_ipv6_cidrs      = coalesce(try(cfg.rdp_allowed_ipv6_cidrs, null), local.instance_defaults.rdp_allowed_ipv6_cidrs)
      # Backward-compatible override: enable_rdp=true forces access mode to "both".
      enable_rdp            = coalesce(try(cfg.enable_rdp, null), local.instance_defaults.enable_rdp)
      effective_access_mode = coalesce(try(cfg.enable_rdp, null), local.instance_defaults.enable_rdp) ? "both" : lower(coalesce(try(cfg.access_mode, null), local.instance_defaults.access_mode))
      enable_ssm            = contains(["ssm", "both"], coalesce(try(cfg.enable_rdp, null), local.instance_defaults.enable_rdp) ? "both" : lower(coalesce(try(cfg.access_mode, null), local.instance_defaults.access_mode)))
      enable_rdp_final      = contains(["rdp", "both"], coalesce(try(cfg.enable_rdp, null), local.instance_defaults.enable_rdp) ? "both" : lower(coalesce(try(cfg.access_mode, null), local.instance_defaults.access_mode)))
      tags                  = coalesce(try(cfg.tags, null), {})
    }
  }

  primary_instance_key = var.primary_instance_key != null ? var.primary_instance_key : sort(keys(local.instances_requested))[0]

  instances_with_existing_eip_requested = { for k, v in local.instances_requested : k => v if v.existing_eip_allocation_id != null }
}

data "aws_eip" "existing" {
  for_each = local.instances_with_existing_eip_requested
  id       = each.value.existing_eip_allocation_id
}

locals {
  instances = {
    for instance_key, cfg in local.instances_requested : instance_key => merge(cfg, {
      existing_eip_in_use = cfg.existing_eip_allocation_id != null ? (try(data.aws_eip.existing[instance_key].association_id, null) != null) : false
      use_existing_eip = cfg.existing_eip_allocation_id != null ? (
        cfg.allow_eip_reassociation || try(data.aws_eip.existing[instance_key].association_id, null) == null
      ) : false
      create_eip_effective = cfg.create_eip || (
        cfg.existing_eip_allocation_id != null &&
        !cfg.allow_eip_reassociation &&
        try(data.aws_eip.existing[instance_key].association_id, null) != null
      )
    })
  }

  ssm_enabled_for_any = anytrue([for _, v in local.instances : v.enable_ssm])

  instances_creating_keypairs  = { for k, v in local.instances : k => v if v.create_key_pair }
  instances_needing_managed_sg = { for k, v in local.instances : k => v if length(v.existing_security_group_ids) == 0 }
  instances_with_existing_eip  = { for k, v in local.instances : k => v if v.use_existing_eip }
  instances_to_create_eip      = { for k, v in local.instances : k => v if !v.use_existing_eip && v.create_eip_effective }
  instances_with_eip_assoc     = { for k, v in local.instances : k => v if v.use_existing_eip || v.create_eip_effective }

  eip_allocation_id_by_instance = {
    for k, v in local.instances : k => (
      v.use_existing_eip ? v.existing_eip_allocation_id : (
        v.create_eip_effective ? aws_eip.windows[k].id : null
      )
    )
  }

  effective_public_ipv4_by_instance = {
    for k, v in local.instances : k => (
      v.use_existing_eip ? data.aws_eip.existing[k].public_ip : (
        v.create_eip_effective ? aws_eip.windows[k].public_ip : aws_instance.windows[k].public_ip
      )
    )
  }
}

check "target_account_id_match" {
  assert {
    condition     = var.target_account_id == null || data.aws_caller_identity.current.account_id == var.target_account_id
    error_message = "Caller account does not match target_account_id. Update target_account_id or refresh credentials."
  }
}

check "existing_network_inputs" {
  assert {
    condition     = var.use_existing_network ? (var.existing_vpc_id != null && var.existing_vpc_id != "" && var.existing_subnet_id != null && var.existing_subnet_id != "") : true
    error_message = "When use_existing_network=true, set both existing_vpc_id and existing_subnet_id."
  }
}

check "instances_non_empty" {
  assert {
    condition     = length(local.instances) > 0
    error_message = "Define at least one instance in var.instances."
  }
}

check "primary_instance_key_exists" {
  assert {
    condition     = var.primary_instance_key == null || contains(keys(local.instances), var.primary_instance_key)
    error_message = "primary_instance_key must match one of the keys in var.instances."
  }
}

check "access_mode_values" {
  assert {
    condition     = alltrue([for _, cfg in local.instances : contains(["ssm", "rdp", "both"], cfg.effective_access_mode)])
    error_message = "Per instance, access_mode must be one of: ssm, rdp, both."
  }
}

check "managed_key_pair_name_uniqueness" {
  assert {
    condition = length(distinct(compact([
      for _, cfg in local.instances : cfg.create_key_pair ? cfg.key_pair_name : null
      ]))) == length(compact([
      for _, cfg in local.instances : cfg.create_key_pair ? cfg.key_pair_name : null
    ]))
    error_message = "Managed key pair names must be unique across instances when create_key_pair=true."
  }
}

check "eip_strategy_per_instance" {
  assert {
    condition     = alltrue([for _, cfg in local.instances : !(cfg.create_eip && cfg.existing_eip_allocation_id != null)])
    error_message = "Per instance, set either create_eip=true OR existing_eip_allocation_id, not both."
  }
}

check "rdp_inputs_when_enabled" {
  assert {
    condition = alltrue([
      for _, cfg in local.instances : cfg.enable_rdp_final ? (
        length(cfg.existing_security_group_ids) > 0 || length(cfg.rdp_allowed_cidrs) + length(cfg.rdp_allowed_ipv6_cidrs) > 0
      ) : true
    ])
    error_message = "When access mode includes RDP and managed SG is used, set rdp_allowed_cidrs or rdp_allowed_ipv6_cidrs."
  }
}

resource "aws_vpc" "this" {
  count                            = var.use_existing_network ? 0 : 1
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  count  = var.use_existing_network ? 0 : 1
  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.base_tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count                           = var.use_existing_network ? 0 : 1
  vpc_id                          = aws_vpc.this[0].id
  availability_zone               = local.az
  cidr_block                      = var.subnet_cidr
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, 0)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-public-subnet" })
}

resource "aws_route_table" "public" {
  count  = var.use_existing_network ? 0 : 1
  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.base_tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route" "ipv4_default" {
  count                  = var.use_existing_network ? 0 : 1
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "ipv6_default" {
  count                       = var.use_existing_network ? 0 : 1
  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.use_existing_network ? 0 : 1
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "instance" {
  for_each = local.instances_needing_managed_sg

  name        = "${var.name_prefix}-${each.key}-instance-sg"
  description = "Windows instance SG for Playwright automation (${each.key})"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = each.value.enable_rdp_final ? [1] : []
    content {
      description      = "RDP"
      from_port        = 3389
      to_port          = 3389
      protocol         = "tcp"
      cidr_blocks      = each.value.rdp_allowed_cidrs
      ipv6_cidr_blocks = each.value.rdp_allowed_ipv6_cidrs
    }
  }

  egress {
    description      = "All outbound IPv4"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }

  egress {
    description      = "All outbound IPv6"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = []
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.base_tags, each.value.tags, { Name = "${var.name_prefix}-${each.key}-instance-sg" })
}

resource "aws_security_group" "vpce" {
  count       = var.create_ssm_vpc_endpoints && local.ssm_enabled_for_any ? 1 : 0
  name        = "${var.name_prefix}-ssm-vpce-sg"
  description = "Allow TLS from VPC to SSM VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "TLS from VPC IPv4"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  dynamic "ingress" {
    for_each = local.vpc_ipv6_cidr != null ? [1] : []
    content {
      description      = "TLS from VPC IPv6"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      ipv6_cidr_blocks = [local.vpc_ipv6_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-ssm-vpce-sg" })
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = var.create_ssm_vpc_endpoints && local.ssm_enabled_for_any ? local.endpoint_services : toset([])

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [local.subnet_id]
  security_group_ids  = [aws_security_group.vpce[0].id]

  tags = merge(local.base_tags, { Name = "${var.name_prefix}-${each.value}-vpce" })
}

resource "aws_iam_role" "ssm" {
  count = local.ssm_enabled_for_any ? 1 : 0
  name  = "${var.name_prefix}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = local.ssm_enabled_for_any ? 1 : 0
  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = local.ssm_enabled_for_any ? 1 : 0
  name  = "${var.name_prefix}-ec2-ssm-profile"
  role  = aws_iam_role.ssm[0].name
  tags  = local.base_tags
}

resource "tls_private_key" "windows" {
  for_each = local.instances_creating_keypairs

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "windows" {
  for_each = local.instances_creating_keypairs

  key_name   = each.value.key_pair_name
  public_key = tls_private_key.windows[each.key].public_key_openssh
  tags       = merge(local.base_tags, each.value.tags, { Name = each.value.key_pair_name })
}

resource "aws_instance" "windows" {
  for_each = local.instances

  ami                         = var.ami_id != null ? var.ami_id : data.aws_ami.windows.id
  instance_type               = each.value.instance_type
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = length(each.value.existing_security_group_ids) > 0 ? each.value.existing_security_group_ids : [aws_security_group.instance[each.key].id]
  iam_instance_profile        = each.value.enable_ssm ? aws_iam_instance_profile.ssm[0].name : null
  key_name                    = each.value.create_key_pair ? aws_key_pair.windows[each.key].key_name : each.value.key_pair_name
  associate_public_ip_address = true
  ipv6_address_count          = each.value.assign_ipv6_address_count
  get_password_data           = each.value.create_key_pair || each.value.key_pair_name != null
  disable_api_termination     = var.prevent_instance_destroy

  user_data = templatefile("${path.module}/user_data.ps1.tftpl", {
    install_choco_packages      = var.install_choco_packages
    choco_packages_json         = jsonencode(var.choco_packages)
    playwright_version          = var.playwright_version
    install_playwright_browsers = var.install_playwright_browsers
    playwright_browsers_json    = jsonencode(var.playwright_browsers)
  })

  root_block_device {
    volume_size           = each.value.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.base_tags, each.value.tags, { Name = "${var.name_prefix}-${each.key}" })

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}

resource "aws_eip" "windows" {
  for_each = local.instances_to_create_eip

  domain = "vpc"
  tags   = merge(local.base_tags, each.value.tags, { Name = "${var.name_prefix}-${each.key}-eip" })
}

resource "aws_eip_association" "windows" {
  for_each = local.instances_with_eip_assoc

  instance_id   = aws_instance.windows[each.key].id
  allocation_id = each.value.use_existing_eip ? each.value.existing_eip_allocation_id : aws_eip.windows[each.key].id
}

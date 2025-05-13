locals {
  aws_partition = data.aws_partition.current.partition

  instance_capacity = merge(var.instance_capacity, { desired = coalesce(var.instance_capacity.desired, var.instance_capacity.min) })
  instance_types    = [for x in var.instance_types : { instance_type = x.type, weighted_capacity = x.weight }]

  tp_edition        = var.tp_edition
  tp_domain         = var.tp_domain
  tp_version        = module.this.enabled ? data.http.tp_cloud_version[0].response_body : ""
  tp_config_encoded = base64encode(yamlencode(local.tp_config))

  tp_config = merge({
    version = "v3"
    teleport = {
      join_params  = var.tp_join_config
      proxy_server = "${local.tp_domain}:443"
      log = {
        output   = "/var/lib/teleport/teleport.log"
        severity = "INFO"
        format   = { output = "text" }
      }
    }
  }, var.tp_config)

  ssm_sessions = {
    enabled          = var.ssm_sessions.enabled
    logs_bucket_name = try(coalesce(var.ssm_sessions.logs_bucket_name, var.logs_bucket_name), "")
  }
}

data "aws_partition" "current" {}

# ================================================================== service ===

module "node" {
  source  = "cloudposse/ec2-autoscale-group/aws"
  version = "0.41.0"

  image_id                = module.this.enabled ? data.aws_ssm_parameter.linux_ami[0].value : ""
  instance_type           = "t3.nano"
  health_check_type       = "EC2"
  user_data_base64        = base64encode(module.this.enabled ? data.template_cloudinit_config.this[0].rendered : "")
  force_delete            = true
  disable_api_termination = false
  update_default_version  = true
  launch_template_version = "$Latest"

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = var.experimental_mode ? 0 : 100
      max_healthy_percentage = 200
    }
  }

  iam_instance_profile_name     = module.this.enabled ? resource.aws_iam_instance_profile.this[0].id : null
  key_name                      = var.instance_key_name
  metadata_http_tokens_required = true

  autoscaling_policies_enabled      = false
  desired_capacity                  = local.instance_capacity.desired
  min_size                          = local.instance_capacity.min
  max_size                          = local.instance_capacity.max
  max_instance_lifetime             = "604800"
  wait_for_capacity_timeout         = "300s"
  tag_specifications_resource_types = ["instance", "volume", "spot-instances-request"]

  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = var.instance_spot.enabled ? 0 : 100
      on_demand_percentage_above_base_capacity = var.instance_spot.enabled ? 0 : 100
      on_demand_allocation_strategy            = "prioritized"
      spot_allocation_strategy                 = var.instance_spot.allocation_strategy
      spot_instance_pools                      = 0
      spot_max_price                           = ""
    }
    override = local.instance_types
  }

  associate_public_ip_address = false
  subnet_ids                  = var.vpc_subnet_ids
  security_group_ids          = concat([module.security_group.id], var.vpc_security_group_ids)

  tags    = merge(module.this.tags, { Name = module.this.id })
  context = module.this.context
}

data "template_cloudinit_config" "this" {
  count = module.this.enabled ? 1 : 0

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/assets/userdata.sh", {
      tp_edition        = local.tp_edition
      tp_domain         = local.tp_domain
      tp_config_encoded = local.tp_config_encoded
    })
  }

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/assets/cloud-config.yaml", {
      cloudwatch_agent_config_encoded = base64encode(templatefile("${path.module}/assets/cloudwatch-agent-config.json", {
        log_group_name = aws_cloudwatch_log_group.this[0].name
      }))
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/assets/provision.sh")
  }
}

resource "aws_cloudwatch_log_group" "this" {
  count = module.this.enabled ? 1 : 0

  name              = module.this.id
  retention_in_days = var.experimental_mode ? 90 : 180
  tags              = module.this.tags
}

# =============================================================== networking ===

module "security_group" {
  source  = "cloudposse/security-group/aws"
  version = "2.2.0"

  attributes                 = []
  vpc_id                     = var.vpc_id
  allow_all_egress           = true
  preserve_security_group_id = true

  rules = concat([], [{
    key                      = "i-healthcheck",
    description              = "allow traffic from others in security-group"
    type                     = "ingress"
    protocol                 = "-1"
    from_port                = 0
    to_port                  = 0
    cidr_blocks              = []
    source_security_group_id = null
    self                     = true
  }])

  tags    = merge(module.this.tags, { Name = module.this.id })
  context = module.this.context
}

# ====================================================================== iam ===

resource "aws_iam_instance_profile" "this" {
  count = module.this.enabled ? 1 : 0

  name = module.this.id
  role = aws_iam_role.this[0].name
}

resource "aws_iam_role" "this" {
  count = module.this.enabled ? 1 : 0

  name                 = module.this.id
  description          = ""
  max_session_duration = "3600"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["ec2.amazonaws.com"] }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = module.this.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count = module.this.enabled ? 1 : 0

  role       = resource.aws_iam_role.this[0].name
  policy_arn = resource.aws_iam_policy.this[0].arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  count = module.this.enabled ? 1 : 0

  role       = resource.aws_iam_role.this[0].name
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "this" {
  count  = module.this.enabled ? 1 : 0
  policy = data.aws_iam_policy_document.this[0].json
}

data "aws_iam_policy_document" "this" {
  count = module.this.enabled ? 1 : 0

  statement {
    sid    = "AllowCWAgentLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:TagResource",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.this[0].arn,
      "${aws_cloudwatch_log_group.this[0].arn}:log-stream:*"
    ]
  }

  dynamic "statement" {
    for_each = local.tp_config.db_service.enabled && length(local.tp_config.db_service.aws) > 0 ? [true] : []

    content {
      sid    = "AllowDatabaseClusterAccess"
      effect = "Allow"
      actions = [
        "redshift:DescribeClusters",
        "redshift:GetClusterCredentials",
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:DescribeDBClusters",
        "rds:ModifyDBCluster",
        "rds-db:connect",
      ]
      resources = [
        "*",
      ]
    }
  }

  dynamic "statement" {
    for_each = local.tp_config.db_service.enabled && length(local.tp_config.db_service.aws) > 0 ? [true] : []

    content {
      sid    = "AllowDatabaseIamAccess"
      effect = "Allow"
      actions = [
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
      ]
      resources = [
        "*", # todo limit which resources
      ]
    }
  }

  dynamic "statement" {
    for_each = var.ssm_sessions.enabled && var.ssm_sessions.logs_bucket_name != "" ? [true] : []

    content {
      sid    = "AllowSessionLogging"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectTagging",
        "s3:GetEncryptionConfiguration",
        "s3:GetBucketLocation",
      ]
      resources = [
        "arn:${local.aws_partition}:s3:::${var.ssm_sessions.logs_bucket_name}",
        "arn:${local.aws_partition}:s3:::${var.ssm_sessions.logs_bucket_name}/*"
      ]
    }
  }
}

# ================================================================== lookups ===

data "aws_vpc" "lookup" {
  count = module.this.enabled ? 1 : 0
  id    = var.vpc_id
}

data "aws_ssm_parameter" "linux_ami" {
  count = module.this.enabled ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "http" "tp_cloud_version" {
  count = module.this.enabled ? 1 : 0
  url   = "https://${local.tp_domain}/v1/webapi/automaticupgrades/channel/stable/cloud/version"
}

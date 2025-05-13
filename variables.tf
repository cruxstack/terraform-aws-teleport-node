# ================================================================== general ===

variable "tp_edition" {
  type    = string
  default = "cloud"
}

variable "tp_domain" {
  type = string
}

variable "tp_join_config" {
  type = object({
    token_name = string
    method     = optional(string, "iam")
  })
}

variable "tp_config" {
  type = object({
    auth_service  = optional(object({ enabled = optional(bool, false) }), {})
    proxy_service = optional(object({ enabled = optional(bool, false) }), {})
    app_service   = optional(object({ enabled = optional(bool, false) }), {})
    ssh_service   = optional(object({ enabled = optional(bool, false) }), {})
    db_service = optional(object({
      enabled = optional(bool, false)
      aws = optional(list(object({
        types   = optional(list(string), [])
        regions = optional(list(string), [])
        tags    = optional(map(string), {})
      })), [])
      resources = optional(list(object({
        labels = optional(map(string), {})
      })), [])
    }), {})
  })
  default = {}
}

# =========================================================== infrastructure ===

variable "instance_capacity" {
  type = object({
    desired = optional(number)
    min     = optional(number, 1)
    max     = optional(number, 3)
  })
  description = "Autoscaling group capacity configuration."
  default     = {}
}

variable "instance_types" {
  type = list(object({
    type   = string
    weight = optional(number, 1)
  }))
  description = "List of instance types and their weighted capacity to be used."
  default     = [{ type = "t3.nano" }, { type = "t3a.nano" }, { type = "t3.micro" }, { type = "t3a.micro" }]
}

variable "instance_key_name" {
  type        = string
  description = "Name of existing SSH key to be assigned to instances."
  default     = ""
}

variable "instance_spot" {
  type = object({
    enabled             = optional(bool, true)
    allocation_strategy = optional(string, "capacity-optimized")
  })
  description = "Configuration of spot instances"
  default     = {}
}

variable "logs_bucket_name" {
  type        = string
  description = "S3 bucket for storing logs."
  default     = ""
}

variable "ssm_sessions" {
  type = object({
    enabled          = optional(bool, false)
    logs_bucket_name = optional(string, "")
  })
  description = "SSM Session Manager configuration with optional bucket for session logs."
  default     = {}
}

# --------------------------------------------------------------- networking ---


variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "IDs of subnets."
  default     = []
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "IDs of security groups to attach to the EC2 instances."
  default     = []
}

# ================================================================== context ===

variable "aws_account_id" {
  type        = string
  description = "AWS account ID."
}

variable "aws_kv_namespace" {
  type        = string
  description = "AWS key-value namespace."
}

variable "aws_region_name" {
  type        = string
  description = "AWS region name."
}

variable "experimental_mode" {
  type        = bool
  description = "Toggle for experimental mode."
}

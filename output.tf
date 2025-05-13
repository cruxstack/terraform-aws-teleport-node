# ================================================================= teleport ===

output "teleport_version" {
  value = module.this.enabled ? local.tp_version : ""
}

output "teleport_config" {
  value = local.tp_config
}

output "security_group_id" {
  value = module.security_group.id
}

output "security_group_name" {
  value = module.security_group.name
}


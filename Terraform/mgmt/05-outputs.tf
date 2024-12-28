output "proxmox_group_all" {
  value     = proxmox_virtual_environment_group.mgmt.*
  sensitive = false
}

output "proxmox_group" {
  value = proxmox_virtual_environment_group.mgmt.group_id
}

output "proxmox_acl_all" {
  value     = proxmox_virtual_environment_acl.mgmt_acl.*
  sensitive = false
}

output "proxmox_acl" {
  value = proxmox_virtual_environment_acl.mgmt_acl.role_id
}

output "proxmox_user_all" {
  value  = proxmox_virtual_environment_user.terraformer.*
  sensitive = true
}

output "proxmox_user" {
  value = proxmox_virtual_environment_user.terraformer.user_id
}

output "proxmox_user_token_all" {
  value     = proxmox_virtual_environment_user_token.user_token.*
  sensitive = true
}

output "proxmox_user_token" {
  value = proxmox_virtual_environment_user_token.user_token.token_name
}


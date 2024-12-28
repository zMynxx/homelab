resource "proxmox_virtual_environment_group" "mgmt" {
  comment  = "Managment group managed by Terraform"
  group_id = "mgmt"
}

resource "proxmox_virtual_environment_acl" "mgmt_acl" {
  role_id = data.proxmox_virtual_environment_role.mgmt_role.role_id
  group_id  = proxmox_virtual_environment_group.mgmt.group_id
  path      = "/"
  propagate = true
}

resource "proxmox_virtual_environment_user" "terraformer" {
  enabled         = true
  user_id         = "terraformer@pve"
  groups          = [proxmox_virtual_environment_group.mgmt.group_id]
  password        = "a-strong-password"
  comment         = "User for Terraform, Managed by Terraform"
  expiration_date = "2024-12-06T12:00:00Z"
  first_name      = "Terraform"
  last_name       = "User"
  email           = "duxlior@gmail.com"
}

resource "proxmox_virtual_environment_user_token" "user_token" {
  comment               = "API Key to be used to manage proxmox using Terraform"
  expiration_date       = "2024-12-06T12:00:00Z"
  token_name            = "terraformer"
  user_id               = proxmox_virtual_environment_user.terraformer.user_id
  privileges_separation = false
}

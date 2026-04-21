resource "proxmox_virtual_environment_group" "mgmt" {
  comment  = "Managment group managed by Terraform"
  group_id = "mgmt"
}

resource "proxmox_virtual_environment_acl" "mgmt_acl" {
  role_id   = data.proxmox_virtual_environment_role.mgmt_role.role_id
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


resource "proxmox_virtual_environment_hardware_mapping_pci" "hba-lsi" {
  comment = "INSPUR SAS9300-i8 HBA LSI IT Mode"
  name    = "HBA-Controller"

  map = [
    {
      comment = "HBA-Controller"
      id      = var.hba_sys_id #"1000:0097"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      iommu_group = 24
      node        = "pve"
      path        = var.hba_path #"0000:04:00.0"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      subsystem_id = var.hba_sys_id #"1000:30e0"
    },
  ]
  mediated_devices = true
}

resource "proxmox_virtual_environment_hardware_mapping_pci" "nic" {
  comment = "HP NC364T PCI Express Quad Port Gigabyte Server Adapter"
  name    = "NIC"

  map = [
    {
      comment = "NIC-Ports12"
      id      = var.nic_sys_id #"8086:10bc"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      iommu_group = 24
      node        = "pve"
      path        = var.nic_path #"0000:09:00.0"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      subsystem_id = var.nic_sys_id #"8086:10bc"
    },
    {
      comment = "NIC-Ports34"
      id      = "8086:10bc"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      iommu_group = 24
      node        = "pve"
      path        = "0000:0a:00.0"
      # This is an optional attribute, but causes a mapping to be incomplete when not defined.
      subsystem_id = "8086:10bc"
    },
  ]
  mediated_devices = true
}

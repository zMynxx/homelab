variable "proxmox_host" {
  description = "Proxmox host"
  default     = "proxmox.example.com"
  type        = string
}

variable "proxmox_port" {
  description = "Proxmox port"
  default     = "8006"
  type        = string
}

variable "username" {
  description = "Proxmox username"
  default     = "root@pam"
  type        = string
}

variable "password" {
  description = "Proxmox password"
  default     = "password"
  type        = string
}

variable "insecure" {
  description = "Proxmox insecure"
  default     = true
  type        = bool
}

##########################
# Network Configurations #
##########################
variable "nic_path" {
  description = "Network Interface Card Path on the proxmox host"
  type        = string
}

variable "nic_sys_id" {
  description = "Network Interface Card system id on the proxmox host"
  type        = string
}

##########################
# HBA LSI Configurations #
##########################
variable "hba_path" {
  description = "Host Bus Adapter Path on the proxmox host"
  type        = string
}

variable "hba_sys_id" {
  description = "Host Bus Adapter system id on the proxmox host"
  type        = string
}

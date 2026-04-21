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

#########################
# API Key Configuration #
#########################
variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  default     = "root@pam"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  default     = "password"
  type        = string
}

variable "proxmox_tls_insecure" {
  description = "Proxmox insecure"
  default     = true
  type        = bool
}

#####################
# SSH Configuration #
#####################
variable "proxmox_ssh_agent" {
  description = "Proxmox SSH Agent"
  default     = true
  type        = bool
}

variable "proxmox_ssh_user" {
  description = "Proxmox SSH User"
  default     = "terraform"
  type        = string
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

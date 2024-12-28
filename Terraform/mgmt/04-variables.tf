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

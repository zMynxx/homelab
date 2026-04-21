provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:${var.proxmox_port}/api2/json"
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    agent    = var.proxmox_ssh_agent
    username = var.proxmox_ssh_user
  }
}

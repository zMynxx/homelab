provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:${var.proxmox_port}/api2/json"
  username = var.username
  password = var.password
  insecure = true
  
  ssh {
    agent = true
    # TODO: uncomment and configure if using api_token instead of password
    username = "root"
    private_key = file("./../../Ansible/00-Init/ansible")
  }
}

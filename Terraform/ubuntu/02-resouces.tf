resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type       = "iso"
  datastore_id       = "local"
  file_name          = "ubuntu-22.04.5-desktop-amd64.iso"
  node_name          = "pve"
  url                = "https://www.releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso"
  checksum           = "bfd1cee02bc4f35db939e69b934ba49a39a378797ce9aee20f6e3e3e728fefbf"
  checksum_algorithm = "sha256"
  upload_timeout     = 1200
}

# After hitting the apply button, do the following:
# 1. Go to the Proxmox web interface and check if the TrueNAS-24.7-dvd-amd64.iso file is downloaded.
# 2. Go to the Proxmox web interface and check if the TrueNAS VM is created.
# 3. Hit the console button to initiate the installation of TrueNAS.
# 4. After the installation is complete, and reboot has been performed, enter the username and password.
# 5. Update the LAN interface to use DHCP.
# 6. Access the TrueNAS web interface using the IP address assigned by the DHCP server.
resource "proxmox_virtual_environment_vm" "ubuntu" {
  name        = "Ubuntu"
  description = "Ubuntu VM Managed by Terraform"
  tags        = ["terraform", "ubuntu"]

  ## Nod
  node_name = "pve"
  vm_id     = 102

  ## QEMU
  agent {
    enabled = true
  }
  stop_on_destroy = true

  on_boot = false
  # startup {
  #   order      = "2"
  #   up_delay   = "30"
  #   down_delay = "30"
  # }

  bios            = "ovmf"
  keyboard_layout = "en-us"

  operating_system {
    type = "l26"
  }
  machine = "q35"

  cpu {
    cores        = 4
    sockets      = 1
    architecture = "x86_64"
    type         = "host"
    flags        = ["+aes"]
  }

  memory {
    dedicated = 8192
    floating  = 8192 # set equal to dedicated to enable ballooning
  }

  ## Storage
  scsi_hardware = "virtio-scsi-single"
  disk {
    datastore_id = "local-lvm"
    size         = 16
    iothread     = true
    discard      = "on"
    interface    = "virtio0"
    file_format  = "raw"
  }

  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
    // file_format = "raw"
  }

  cdrom {
    enabled = true
    file_id = proxmox_virtual_environment_download_file.ubuntu.id
  }

  ## Network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
}

resource "proxmox_virtual_environment_download_file" "opnsense" {
  content_type       = "iso"
  datastore_id       = "local"
  file_name          = "OPNsense-24.7-dvd-amd64.img"
  node_name          = "pve"
  url                = "https://pkg.opnsense.org/releases/24.7/OPNsense-24.7-dvd-amd64.iso.bz2"
  checksum           = "4452df716417cac324bb06322fc4428870ac2a64fd6ae47675a421e8db0a18b5"
  checksum_algorithm = "sha256"
}

# After hitting the apply button, do the following:
# 1. Go to the Proxmox web interface and check if the OPNsense-24.7-dvd-amd64.iso file is downloaded.
# 2. Go to the Proxmox web interface and check if the OPNsense VM is created.
# 3. Hit the console button to initiate the installation of OPNsense.
# 4. After the installation is complete, and reboot has been performed, enter the username and password.
# 5. Update the LAN interface to use DHCP.
# 6. Access the OPNsense web interface using the IP address assigned by the DHCP server.
resource "proxmox_virtual_environment_vm" "opnsense" {
  name        = "OPNsense"
  description = "OPNsense Firewall Managed by Terraform"
  tags        = ["terraform", "opnsense"]

  ## Nod
  node_name = "pve"
  vm_id     = 100

  ## QEMU
  agent {
    enabled = true 
  }
  stop_on_destroy = true

  on_boot = true
  startup {
    order      = "1"
    up_delay   = "30"
    down_delay = "30"
  }

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
    size         = 64
    iothread     = true
    discard      = "on"
    interface    = "virtio0"
    file_format  = "raw"
  }

  efi_disk {
    datastore_id = "local-lvm"
    type = "4m"
    // file_format = "raw"
  }

  cdrom {
    enabled                               = true
    file_id                               = "local:iso/OPNsense-24.7-dvd-amd64.iso"
    # file_id                               = proxmox_virtual_environment_download_file.opnsense.id
  }

  ## Network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
}

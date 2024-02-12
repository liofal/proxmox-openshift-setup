terraform {
  backend "s3" {
    bucket         = "lfa-speos-test"
    key            = "terraform/state"
    encrypt        = true
  }
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "2.9.11"
    }
  }
}

provider "proxmox" {
  pm_api_url  = var.api_url
  # pm_user     = var.user
  # pm_password = var.passwd
  pm_api_token_id     = var.token_id
  pm_api_token_secret = var.token_secret
  # Leave to "true" for self-signed certificates
  pm_tls_insecure = true
  pm_debug        = true
}

locals {
  vm_settings = {
    "master0"      = { macaddr = "7A:00:00:00:03:01", cores = 4, ram = 12288, vmid = 801, os = "pxe-client", boot = true },
    "master1"      = { macaddr = "7A:00:00:00:03:02", cores = 4, ram = 12288, vmid = 802, os = "pxe-client", boot = true },
    "master2"      = { macaddr = "7A:00:00:00:03:03", cores = 4, ram = 12288, vmid = 803, os = "pxe-client", boot = true },
    "worker0"      = { macaddr = "7A:00:00:00:03:04", cores = 2, ram = 12288, vmid = 804, os = "pxe-client", boot = true },
    # "worker1"      = { macaddr = "7A:00:00:00:03:05", cores = 2, ram = 4096, vmid = 805, os = "pxe-client", boot = true },
    # "worker2"      = { macaddr = "7A:00:00:00:03:06", cores = 2, ram = 4096, vmid = 806, os = "pxe-client", boot = true },
    # "bootstrap"    = { macaddr = "7A:00:00:00:03:07", cores = 4, ram = 12288, vmid = 807, os = "pxe-client", boot = true },
    # "bootstrap2"    = { macaddr = "7A:00:00:00:03:09", cores = 4, ram = 8192, vmid = 809, os = "a2cent", boot = false },
  }
  services_settings = {
    "okd-services" = { macaddr = "7A:00:00:00:03:08", cores = 4, ram = 4096, vmid = 808, os = "a2cent", boot = true }
  }
  bridge = "vmbr0"
  vlan   = 2
  lxc_settings = {
  }
}

/* Configure cloud-init User-Data with custom config file */
resource "proxmox_vm_qemu" "cloudinit-nodes" {
  for_each    = local.vm_settings
  name        = each.key
  vmid        = each.value.vmid
  target_node = var.target_host
  clone       = each.value.os
  full_clone = false
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  oncreate    = each.value.boot         # start once created
  agent       = 0
  # pool         = "okd"

  cores    = each.value.cores
  memory   = each.value.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disk {
    slot    = 0
    size    = "100G"
    type    = "scsi"
    storage = "local-lvm"
    #iothread = 1
  }
  network {
    model   = "virtio"
    bridge  = local.bridge
    tag     = local.vlan
    firewall = false
    macaddr = each.value.macaddr
  }
}

resource "proxmox_vm_qemu" "cloudinit-services" {
  for_each    = local.services_settings
  name        = each.key
  vmid        = each.value.vmid
  target_node = var.target_host
  clone       = each.value.os
  full_clone  = false
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  oncreate    = each.value.boot         # start once created
  agent       = 0
  # pool         = "okd"

  cores    = each.value.cores
  memory   = each.value.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disk {
    slot    = 0
    size    = "100G"
    type    = "scsi"
    storage = "local-lvm"
    #iothread = 1
  }
  network {
    model   = "virtio"
    bridge  = local.bridge
    firewall = false
    macaddr = "7A:00:00:00:03:10"
  }
  network {
    model   = "virtio"
    bridge  = local.bridge
    tag     = local.vlan
    firewall = false
    macaddr = each.value.macaddr
  }
}

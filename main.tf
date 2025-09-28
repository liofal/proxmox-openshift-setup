##############################
# Creating cloud-init devices.
##############################
resource "proxmox_vm_qemu" "service-node" {
  depends_on  = [proxmox_pool.cluster]
  name        = local.service.name
  vmid        = local.service.vmid
  target_node = var.target_host
  clone       = local.service.os
  full_clone  = true
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  agent       = 1
  tags        = "${local.main.target},service"
  pool        = "${local.main.target}-cluster"
  onboot      = true
  vm_state    = "running" #local.service.boot # start once created


  cores    = local.service.cores
  memory   = local.service.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = "120G"
          discard = true
        }
      }
    }
    ide {
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }
  network {
    id      = 0
    model   = "virtio"
    bridge  = local.network.mgmt_bridge
    macaddr = local.service.mgmt_macaddr
    tag     = local.network.mgmt_vlan == 0 ? null : local.network.mgmt_vlan
  }

  network {
    id      = 1
    model   = "virtio"
    bridge  = local.network.bridge
    tag     = local.network.vlan
    macaddr = local.service.macaddr
  }

  # cloud-init config
  cicustom   = "vendor=local:snippets/centos-qemu-agent.yml" # This installs the Qemu Guest Agent. Install the file in /var/lib/vz/snippets on proxmox host
  ciupgrade  = true
  nameserver = local.network.resolver
  ipconfig0  = "ip=${local.service.mgmt_ip}/${local.network.mgmt_prefix}"
  ipconfig1  = "ip=${local.service.ip}/24,gw=${local.network.lab_gw}"
  skip_ipv6  = true
  ciuser     = var.ansible_user
  cipassword = var.ansible_pwd
  sshkeys    = var.ansible_ssh_public_key

  lifecycle {
    ignore_changes = [pool, bootdisk]
  }
}

###################################
# Creating all PXE booting devices.
###################################
resource "proxmox_vm_qemu" "pxe-nodes" {
  depends_on = [proxmox_pool.cluster]

  for_each    = local.all_pxe_nodes
  name        = "${local.main.env}-${local.main.target}-${each.key}"
  vmid        = each.value.vmid
  target_node = var.target_host
  clone       = each.value.os
  full_clone  = true
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  agent       = 0
  tags        = local.main.target
  pool        = "${local.main.target}-cluster"

  onboot   = true
  vm_state = each.value.boot #each.value.boot # start once created

  cores    = each.value.cores
  memory   = each.value.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disk {
    slot    = "scsi0"
    size    = "200G"
    type    = "disk"
    storage = "local-lvm"
    discard = true
    #iothread = 1
  }
  network {
    id      = 0
    model   = "virtio"
    bridge  = local.network.bridge
    tag     = local.network.vlan
    macaddr = each.value.macaddr
  }

  # cloud-init config for PXE nodes
  nameserver = local.network.resolver
  ipconfig0  = "ip=${each.value.ip}/24,gw=${local.network.lab_gw}"
  skip_ipv6  = true

  lifecycle {
    ignore_changes = [pool, disk, bootdisk]
  }
}

resource "proxmox_pool" "cluster" {
  count   = var.manage_pool ? 1 : 0
  poolid  = "${local.main.target}-cluster"
  comment = "All ${local.main.target} VMs"
}

resource "local_file" "ansible_inventory" {
  content = templatefile("templates/hosts.tmpl",
    {
      service_ip    = local.service.ip
      service_mgmt_ip = local.service.mgmt_ip
      bootstrap_ip  = local.bootstrap.ip
      masters       = [for j in local.masters : j.ip]
      workers       = [for j in local.workers : j.ip]
      hypervisor_ip = local.network.hypervisor
    }
  )
  filename = "inventory/hosts.ini"
}

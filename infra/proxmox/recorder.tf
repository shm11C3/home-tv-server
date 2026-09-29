resource "proxmox_download_file" "debian_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore_id
  node_name    = var.node_name
  url          = var.debian_cloud_image_url
  file_name    = var.debian_cloud_image_file_name
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "recorder" {
  name      = var.recorder_name
  node_name = var.node_name
  vm_id     = var.recorder_vm_id

  description = "自宅 TV 録画サーバ VM（OpenTofu 管理）"
  tags        = ["home", "recorder", "iac"]

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single" # iothread を効かせるために必要
  on_boot       = true
  started       = true

  agent {
    enabled = var.guest_agent_enabled
    trim    = var.guest_agent_enabled
  }

  cpu {
    cores = var.recorder_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.recorder_memory_mb
  }

  efi_disk {
    datastore_id = var.vm_datastore_id
    type         = "4m"
  }

  # cloud image はシリアルコンソールで起動する。Proxmox UI から見えるようにする
  serial_device {}

  vga {
    type = "serial0"
  }

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = proxmox_download_file.debian_cloud_image.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = var.recorder_os_disk_gb
  }

  # 録画用 HDD を raw ブロックデバイスとして VM に渡す（任意、experimental）
  dynamic "disk" {
    for_each = { for i, d in var.recording_disk_passthrough : i => d }
    content {
      datastore_id      = ""
      path_in_datastore = disk.value.device
      file_format       = "raw"
      interface         = "scsi${disk.key + 1}"
      size              = disk.value.size_gb
      backup            = false
      iothread          = true
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.vm_datastore_id

    ip_config {
      ipv4 {
        address = var.recorder_ipv4_address
        gateway = var.recorder_ipv4_gateway
      }
    }

    user_account {
      username = var.admin_user
      keys     = var.ssh_public_keys
    }
  }

  dynamic "hostpci" {
    for_each = var.pci_passthrough
    content {
      device  = hostpci.value.device
      mapping = hostpci.value.mapping
      pcie    = hostpci.value.pcie
      rombar  = hostpci.value.rombar
    }
  }

  dynamic "usb" {
    for_each = var.usb_passthrough
    content {
      mapping = usb.value.mapping
      usb3    = usb.value.usb3
    }
  }

  lifecycle {
    ignore_changes = [
      # イメージは URL 変更時にだけ再取得される。それを理由に VM を再作成しない
      disk[0].import_from,
    ]
  }

  depends_on = [
    proxmox_hardware_mapping_pci.this,
    proxmox_hardware_mapping_usb.this,
  ]
}

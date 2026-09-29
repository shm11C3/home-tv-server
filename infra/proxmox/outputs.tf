output "recorder_vm_id" {
  value = proxmox_virtual_environment_vm.recorder.vm_id
}

output "recorder_vm_name" {
  value = proxmox_virtual_environment_vm.recorder.name
}

output "recorder_ipv4_addresses" {
  description = "QEMU agent が報告するゲスト IP。guest_agent_enabled = true になるまで空"
  value       = var.guest_agent_enabled ? proxmox_virtual_environment_vm.recorder.ipv4_addresses : []
}

output "pci_hardware_mappings" {
  value = keys(proxmox_hardware_mapping_pci.this)
}

output "usb_hardware_mappings" {
  value = keys(proxmox_hardware_mapping_usb.this)
}

# クラスタ全体のハードウェア Resource Mapping
# VM 定義に生の PCI アドレスが出てこないよう、VM とは別ファイルにしている

resource "proxmox_hardware_mapping_pci" "this" {
  for_each = var.pci_hardware_mappings

  name    = each.key
  comment = each.value.comment

  map = [
    {
      node         = var.node_name
      id           = each.value.id
      path         = each.value.path
      subsystem_id = each.value.subsystem_id
      iommu_group  = each.value.iommu_group
      comment      = each.value.comment
    },
  ]
}

resource "proxmox_hardware_mapping_usb" "this" {
  for_each = var.usb_hardware_mappings

  name    = each.key
  comment = each.value.comment

  map = [
    {
      node    = var.node_name
      id      = each.value.id
      path    = each.value.path
      comment = each.value.comment
    },
  ]
}

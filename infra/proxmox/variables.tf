# ---------------------------------------------------------------------------
# Proxmox 接続
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "Proxmox API エンドポイント（例: https://192.168.1.10:8006/）"
  type        = string
}

variable "proxmox_insecure" {
  description = "bootstrap 期間中は Proxmox API の自己署名証明書を許可する"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Proxmox ノード名"
  type        = string
  default     = "pve"
}

# ---------------------------------------------------------------------------
# ストレージ
# ---------------------------------------------------------------------------

variable "image_datastore_id" {
  description = <<-EOT
    Debian cloud image をキャッシュするデータストア
    "Import" コンテンツタイプを許可している必要がある
    （Datacenter > Storage > <datastore> > Content）。docs/bootstrap.md 参照
  EOT
  type        = string
  default     = "local"
}

variable "vm_datastore_id" {
  description = "recorder VM の OS ディスク、EFI 変数、cloud-init ドライブを置くデータストア"
  type        = string
  default     = "local-lvm"
}

variable "debian_cloud_image_url" {
  description = "Debian 13 generic cloud image（非圧縮 qcow2）。厳密な再現性が必要になったら日付付きイメージに固定する"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "debian_cloud_image_file_name" {
  description = "import データストアに保存するファイル名"
  type        = string
  default     = "debian-13-generic-amd64.qcow2"
}

# ---------------------------------------------------------------------------
# recorder VM のサイズ
# ---------------------------------------------------------------------------

variable "recorder_vm_id" {
  description = "固定の Proxmox VM ID"
  type        = number
  default     = 200
}

variable "recorder_name" {
  type    = string
  default = "recorder"
}

variable "recorder_cpu_cores" {
  type    = number
  default = 6
}

variable "recorder_memory_mb" {
  description = "専有メモリ。PCI passthrough はゲストメモリを固定するため、バルーニングは意図的に無効"
  type        = number
  default     = 8192
}

variable "recorder_os_disk_gb" {
  type    = number
  default = 48
}

variable "guest_agent_enabled" {
  description = <<-EOT
    provider が QEMU guest agent と通信するかどうか
    初回 apply では false のままにする。Debian cloud image に qemu-guest-agent が入っている
    保証はなく、有効なのにエージェントが居ないと apply / refresh が 15 分ほどブロックする
    Ansible の base ロールでエージェントを入れたあとに true にする
  EOT
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# ネットワーク
# ---------------------------------------------------------------------------

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "recorder_ipv4_address" {
  description = "最初は dhcp、その後 192.168.1.50/24 のような CIDR に切り替える"
  type        = string
  default     = "dhcp"
}

variable "recorder_ipv4_gateway" {
  description = "DHCP の場合は null のまま"
  type        = string
  default     = null
  nullable    = true
}

variable "admin_user" {
  type    = string
  default = "recorder"
}

variable "ssh_public_keys" {
  description = "cloud-init で投入する SSH 公開鍵"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# ハードウェア Resource Mapping（Datacenter > Resource Mappings）
#
# いずれも任意。実機ができて `lspci -nn` / `lsusb` / IOMMU グループを記録するまでは
# 空のままにしておく。マッピング名は下の pci_passthrough / usb_passthrough から参照する
# ---------------------------------------------------------------------------

variable "pci_hardware_mappings" {
  description = <<-EOT
    作成する PCI Resource Mapping。キーはマッピング名（例: "gpu-gtx1050"）
    id           = lspci -nn の "vendor:device"。例: "10de:1c81"
    path         = PCI パス。例: "0000:0a:00.0"（GPU オーディオなど全ファンクションを含めるなら "0000:0a:00"）
    subsystem_id = lspci -nnv で分かるサブシステムの "vendor:device"
    iommu_group  = /sys/kernel/iommu_groups の番号
  EOT
  type = map(object({
    comment      = optional(string, "")
    id           = string
    path         = string
    subsystem_id = optional(string)
    iommu_group  = optional(number)
  }))
  default = {}
}

variable "usb_hardware_mappings" {
  description = <<-EOT
    作成する USB Resource Mapping。キーはマッピング名（例: "tuner", "bcas-reader"）
    id   = lsusb の "vendor:product"。例: "0511:083f"
    path = 任意。デバイス ID ではなく物理ポートに固定したい場合の "1-8.2" のようなポートパス
  EOT
  type = map(object({
    comment = optional(string, "")
    id      = string
    path    = optional(string)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# recorder VM に接続するデバイス
# ---------------------------------------------------------------------------

variable "pci_passthrough" {
  description = "VM に接続する PCI マッピング名（GPU、PCIe チューナー、SATA コントローラ丸ごと）"
  type = list(object({
    device  = string # hostpci0..hostpci15
    mapping = string # pci_hardware_mappings のキー、または既存のマッピング名
    pcie    = optional(bool, true)
    rombar  = optional(bool, true)
  }))
  default = []
}

variable "usb_passthrough" {
  description = "VM に接続する USB マッピング名（USB チューナー、B-CAS カードリーダ）"
  type = list(object({
    mapping = string
    usb3    = optional(bool, false)
  }))
  default = []
}

variable "recording_disk_passthrough" {
  description = <<-EOT
    物理ディスクを raw ブロックデバイスとして VM に丸ごと渡す。安定した
    /dev/disk/by-id/... を使い、/dev/sdX は使わない。インターフェースは scsi1 から
    provider の experimental な path_in_datastore 機能を使うため、API ユーザーは
    root@pam である必要がある（非 root の API トークンではホストのブロックデバイスを
    接続できない）。代替: SATA コントローラが独立した IOMMU グループにあるなら
    pci_passthrough で passthrough する
  EOT
  type = list(object({
    device  = string
    size_gb = number # 参考値。実ディスク容量（GiB、切り捨て）と一致させる
  }))
  default = []
}

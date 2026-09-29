provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # 認証情報は意図的にここに書かない
  # シェルで PROXMOX_VE_API_TOKEN を export する
}

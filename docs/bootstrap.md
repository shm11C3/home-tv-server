# 物理ホストの bootstrap

ここが意図的に手作業として残す境界。以下が終わったら Ansible（ホスト）、OpenTofu（VM）、Ansible（ゲスト）に引き渡す。

## 1. ハードウェア

- GTX 1050 を装着する。
- TV チューナーは選定後に装着する。PLEX の PCIe モデルは内部的には USB デバイスなので `lsusb` に出る。
- Proxmox / VM 用 SSD を接続する。
- SMART チェック済みの HDD だけを接続する。
- 有線 LAN を使う。

## 2. BIOS / UEFI

最低限以下を確認する。

- SVM / AMD 仮想化 有効
- IOMMU 有効
- PCIe passthrough の構成上必要なら Above 4G Decoding 有効
- CSM 無効（純 UEFI）。GPU を UEFI GOP ROM で起動させるため

このリポジトリに合わせるためだけに無関係なファームウェア設定を変えないこと。

## 3. Proxmox VE のインストール

現行の Proxmox VE 9.x を SSD にインストールし、ホストに固定 LAN アドレスを与える。

インストール後:

```bash
pveversion -v
ip addr
```

Debian イメージをキャッシュするデータストアで `Import` コンテンツタイプを有効化する
（Datacenter > Storage > `local` > Content に "Import" を追加）。OpenTofu は
`content_type = "import"` で qcow2 をここへダウンロードする。

## 4. ハードウェア識別子の記録

```bash
for g in /sys/kernel/iommu_groups/*; do echo "IOMMU group ${g##*/}"; lspci -nns "$(ls "$g"/devices | head -1)"; ls "$g"/devices; done
lspci -nnk
lsusb
ls -l /dev/disk/by-id/ | grep -v part
smartctl -a /dev/disk/by-id/ata-...
lsblk -f
```

`terraform.tfvars` / `host_vars` に記録するもの:

- GTX 1050 のビデオ・オーディオ両ファンクションの ID（`10de:xxxx`）、PCI パス、サブシステム ID、IOMMU グループ
- チューナーの USB vendor:product、B-CAS リーダの vendor:product
- SATA コントローラを passthrough する場合はその PCI ID / IOMMU グループ
- 各録画 HDD の `/dev/disk/by-id/...`、既存ファイルシステム、容量

実値（ディスクのシリアル、アドレス）は gitignore されたファイルにだけ書く。

## 5. ホスト側 passthrough 前提設定

```bash
cp ansible/inventory/hosts.example.yml ansible/inventory/hosts.yml   # pve のアドレスを記入
make host
# Proxmox ホストを再起動してから:
dmesg | grep -i -e iommu -e vfio
lspci -nnk | grep -A3 -i nvidia    # "Kernel driver in use: vfio-pci" になっていること
```

この実行が意味を持つには、`host_vars/pve.yml` の `proxmox_host_vfio_pci_ids` に GPU（両ファンクション）を列挙しておく必要がある。

## 6. API 認証情報の作成

OpenTofu 用に専用の Proxmox ユーザー / API トークンを作り、ローカルで環境変数として渡す。

```bash
export PROXMOX_VE_API_TOKEN='terraform@pve!provider=...'
```

権限は bpg provider のドキュメントにある権限セットから始め、初回の plan / apply が通ってから絞る。`recording_disk_passthrough`（ホストのブロックデバイス）は `root@pam` でしか使えない。権限を絞ったトークンを維持したい場合は SATA コントローラを PCI で passthrough する。

## 7. 実値の記入

```bash
cp infra/proxmox/terraform.tfvars.example infra/proxmox/terraform.tfvars
```

最低限 `proxmox_endpoint`、`node_name`、データストア ID、SSH 公開鍵、ネットワークアドレスを設定する。まず素の VM を確認したい場合は、初回 apply では `guest_agent_enabled = false` のまま、ハードウェアのセクションも空にしておく。

## 8. recorder VM のプロビジョニング

```bash
make init
make plan
make apply
```

VM は Debian 13 generic cloud image を使い、シリアルコンソール（Proxmox UI から見える）で起動し、既定では DHCP。

## 9. ゲスト OS の構成

```bash
cp ansible/host_vars/recorder.yml.example ansible/host_vars/recorder.yml
make configure
```

その後 `terraform.tfvars` の `guest_agent_enabled = true` にして再度 `make apply` する。これで OpenTofu がゲスト IP を読めるようになり、graceful shutdown も使える。

## 10. 録画ディスクの追加

SMART とファイルシステム内容を確認したうえで、安定した `/dev/disk/by-id/...` パスを使う。`recording_disk_passthrough`（OpenTofu）に追加するかコントローラを passthrough し、`make apply` 後に VM 内で `lsblk -f` に出ることを確認してから `host_vars/recorder.yml` の `recording_disks` を埋めて `make configure` する。

このリポジトリのロールはディスクを自動フォーマットしない。

## 11. ハードウェア機能の有効化

1. GPU: マッピングと `pci_passthrough` を追加して `make apply`、`nvidia_enabled: true` にして `make configure`、VM 内で `nvidia-smi` と `docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi` を確認。
2. チューナー: USB マッピングと `usb_passthrough` を追加して `make apply`、`tuner_enabled: true` と `tuner_px4_drv_firmware_zip_url` を設定して `make configure`、`ls /dev/px4video*` を確認。
3. アプリ: `apps_enabled: true` にして `make configure`。その後 `apps/recorder/compose.yml` の `/dev/px4video*` のコメントを外し、`mirakurun/tuners.yml` のチューナーを有効化してチャンネルスキャンを実行。
4. デプロイ: `github_runner_enabled: true` にし、`GITHUB_TOKEN=$(gh auth token) make configure` で runner を登録する（トークンには repo の Administration 権限が必要。登録後は不要）。GitHub の Settings > Actions > Runners に `recorder` ラベルで現れたら、リポジトリ変数 `DEPLOY_ENABLED` を `true` にする。

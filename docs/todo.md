# TODO: 録画サーバが使えるようになるまで

着手順に並べている。各段階の詳細な手順は [bootstrap.md](bootstrap.md) を参照。

## 0. リポジトリ側（実機不要）

- [ ] GitHub へ push し、Settings > Actions で「fork からの workflow 実行は承認必須」を設定
- [ ] Collaborators only の PR 制限下で Dependabot が PR を作れるか確認
- [ ] GitHub ホスト runner 上で CI が green になることを確認（`docker compose config`、`ansible-lint`）
- [ ] チューナーの機種を決める。PLEX 以外なら `roles/tuner`、`mirakurun/tuners.yml`、USB マッピングを書き直す

## 1. 物理組み立てと Proxmox（手作業）

- [ ] 組み立て、BIOS（SVM、IOMMU、Above 4G Decoding、CSM 無効）
- [ ] Proxmox VE 9 インストール、固定 IP
- [ ] `local` データストアに Import コンテンツタイプを追加
- [ ] `lspci -nnk`、IOMMU グループ、`lsusb`、`/dev/disk/by-id`、SMART、`lsblk -f` を記録（bootstrap.md 手順 4）
- [ ] SATA コントローラが独立した IOMMU グループにあるか確認し、HDD の渡し方を決める
  - コントローラ passthrough（推奨）: `pci_hardware_mappings` と `pci_passthrough` に追加。制限付きトークンで運用できる
  - raw ディスク passthrough: `recording_disk_passthrough` に追加。apply には root@pam のパスワード認証が必要
- [ ] OpenTofu 用のロールと API トークンを作成（bootstrap.md 手順 6）

## 2. ホスト設定と VM 作成

- [ ] `ansible/inventory/hosts.yml` と `ansible/host_vars/pve.yml`（`proxmox_host_vfio_pci_ids`）を作成
- [ ] `make host` → ホスト再起動 → GPU が vfio-pci に付いていることを確認
- [ ] `infra/proxmox/terraform.tfvars` を作成。初回は passthrough 無し、`guest_agent_enabled = false`
- [ ] `make init plan apply` で素の VM が起動することを確認
  - 確認: Import 経由の qcow2 取り込みが通るか
  - 確認: シリアルコンソールから cloud-init のユーザーでログインできるか

## 3. ゲスト構成

- [ ] `ansible/host_vars/recorder.yml` を作成して `make configure`（base / docker / storage / tailscale）
  - 確認: qemu-guest-agent が起動するか
  - 確認: mergerfs のオプション（`cache.files=off` 等）でマウントが通るか
- [ ] `guest_agent_enabled = true` にして `make apply`
- [ ] `TAILSCALE_AUTH_KEY` を渡して tailnet に参加。tailnet 側の ACL を用意

## 4. ハードウェア機能の有効化

- [ ] GPU: `pci_hardware_mappings` と `pci_passthrough` を追加して `make apply`
- [ ] `nvidia_enabled: true` で `make configure`。`nvidia-smi` と `docker run --rm --gpus all ... nvidia-smi` で確認
- [ ] チューナーと B-CAS リーダ: `usb_hardware_mappings` と `usb_passthrough` を追加して `make apply`
- [ ] `tuner_enabled: true` と `tuner_px4_drv_firmware_zip_url` を設定して `make configure`。`/dev/px4video*` を確認
  - px4_drv の導入手順は実機未検証。崩れる可能性が最も高い箇所
- [ ] HDD: 渡し方に応じて `make apply` → VM 内で `lsblk -f` → `recording_disks` を埋めて `make configure`
- [ ] `/srv/recordings` に書き込めることを確認。`findmnt /srv/recordings` が `fuse.mergerfs` であること

## 5. アプリ起動（ここまでで「使える」状態）

- [ ] `apps_enabled: true` で `make configure`。`apps/recorder/.env` のパスワードを変更
- [ ] `compose.yml` の `/dev/px4video*` を有効化、`tuners.yml` の `isDisabled` を外す
- [ ] Mirakurun でチャンネルスキャン（GR / BS / CS）。B-CAS でデスクランブルできているか確認
- [ ] EPGStation で EPG 取得 → 手動録画 1 本 → 再生確認
  - 確認: EPGStation イメージ内の ffmpeg パス（`/usr/local/bin/ffmpeg`）
  - 確認: `enc.js` の libx264 エンコードが通るか

## 6. 仕上げ

- [ ] NVENC: `ENCODER=nvenc` と compose の GPU 予約を有効化し、エンコードが GPU に乗ることを確認
- [ ] self-hosted runner: `github_runner_enabled: true` で登録、`DEPLOY_ENABLED` を true にして deploy を一度手動実行
- [ ] バックアップ: timer の動作確認。`/var/backups/recorder` を VM 外へ退避する経路（rsync か vzdump）を決めて実装
- [ ] Fire TV に Kodi と EPGStation プラグインを入れて視聴確認
- [ ] Proxmox 側で VM の vzdump スケジュール
- [ ] CM 検出（join_logo_scp / comskip）。フェーズ 2

## 判断待ち

| 項目                 | 決まる時期               | 影響範囲                                   |
| -------------------- | ------------------------ | ------------------------------------------ |
| チューナーの機種     | 購入時                   | `roles/tuner`、`tuners.yml`、USB マッピング |
| HDD の渡し方         | 実機の IOMMU グループ確認後 | OpenTofu の変数、apply 時の認証方式        |
| バックアップの退避先 | 後回しで可               | `roles/backup` の拡張                      |

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_config
require_proxmox
ensure_dirs
check_storage_exists "$PVE_STORAGE"
check_storage_exists "$SNIPPET_STORAGE"

create_cloud_template() {
  local vmid="$1"
  local name="$2"
  local image="$3"
  local memory="$4"
  local cores="$5"

  [[ -f "$image" ]] || fail "Image introuvable: $image. Lance scripts/refresh-images.sh."

  info "Préparation template $name ($vmid)"

  if qm status "$vmid" >/dev/null 2>&1; then
    warn "VMID $vmid existe déjà. Suppression."
    qm stop "$vmid" >/dev/null 2>&1 || true
    qm destroy "$vmid" --purge 1
  fi

  qm create "$vmid" \
    --name "$name" \
    --memory "$memory" \
    --sockets 1 \
    --cores "$cores" \
    --cpu host \
    --net0 "virtio,bridge=${PVE_BRIDGE}" \
    --scsihw virtio-scsi-pci \
    --ostype l26 \
    --agent enabled=1 \
    --tablet 0

  qm importdisk "$vmid" "$image" "$PVE_STORAGE"

  local disk_vol
  disk_vol="$(get_unused_disk_volume "$vmid")"
  [[ -n "$disk_vol" ]] || fail "Impossible de retrouver le disque importé pour VMID $vmid"

  qm set "$vmid" \
    --scsi0 "${disk_vol},discard=on,ssd=1" \
    --ide2 "${PVE_STORAGE}:cloudinit" \
    --boot order=scsi0 \
    --serial0 socket \
    --vga serial0 \
    --ipconfig0 ip=dhcp

  qm template "$vmid"
  ok "Template créé: $name ($vmid)"
}

create_cloud_template \
  "$TPL_UBUNTU_SERVER" \
  "tmpl-ubuntu-${UBUNTU_SERIES}-latest" \
  "$IMAGE_DIR/ubuntu-${UBUNTU_SERIES}-latest.img" \
  2048 \
  2

create_cloud_template \
  "$TPL_DEBIAN_SERVER" \
  "tmpl-debian-${DEBIAN_VERSION}-${DEBIAN_SERIES}-latest" \
  "$IMAGE_DIR/debian-${DEBIAN_VERSION}-${DEBIAN_SERIES}-latest.qcow2" \
  2048 \
  2

create_cloud_template \
  "$TPL_KALI_CLOUD" \
  "tmpl-kali-cloud-latest" \
  "$IMAGE_DIR/kali-cloud-latest-amd64.img" \
  4096 \
  2

ok "Templates Proxmox créés. Tu peux lancer scripts/create-vm.sh."

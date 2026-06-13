#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_config
need_cmd curl
need_cmd wget
need_cmd grep
need_cmd awk
need_cmd sha256sum
need_cmd tar
ensure_dirs

ok "Cache images: $IMAGE_DIR"

verify_sha256_file() {
  local sums_file="$1"
  local filename="$2"
  local workdir="$3"

  [[ -f "$sums_file" ]] || fail "Checksum introuvable: $sums_file"
  (
    cd "$workdir"
    grep " ${filename}$" "$sums_file" | sha256sum -c -
  ) || fail "Checksum invalide pour $filename"
}

download_ubuntu() {
  local series="$UBUNTU_SERIES"
  local base="https://cloud-images.ubuntu.com/${series}/current"
  local filename="${series}-server-cloudimg-amd64.img"
  local target="$IMAGE_DIR/ubuntu-${series}-latest.img"

  info "Téléchargement Ubuntu cloud image: $series"
  wget -c "$base/$filename" -O "$target"
  wget -q "$base/SHA256SUMS" -O "$IMAGE_DIR/ubuntu-${series}-SHA256SUMS"
  cp "$target" "$IMAGE_DIR/$filename"
  verify_sha256_file "$IMAGE_DIR/ubuntu-${series}-SHA256SUMS" "$filename" "$IMAGE_DIR"
  rm -f "$IMAGE_DIR/$filename"
  ok "Ubuntu image prête: $target"
}

download_debian() {
  local series="$DEBIAN_SERIES"
  local version="$DEBIAN_VERSION"
  local filename="debian-${version}-genericcloud-amd64.qcow2"
  local base="https://cloud.debian.org/images/cloud/${series}/latest"
  local target="$IMAGE_DIR/debian-${version}-${series}-latest.qcow2"

  info "Téléchargement Debian cloud image: Debian $version / $series"
  wget -c "$base/$filename" -O "$target"

  # Debian also publishes SHA512SUMS, but mirror/index availability varies.
  # We download the official cloud image URL directly and fail hard if HTTP fails.
  [[ -s "$target" ]] || fail "Image Debian vide ou introuvable: $target"
  ok "Debian image prête: $target"
}

download_kali() {
  local base="https://kali.download/cloud-images/current"
  local index archive target extract_dir image_found

  info "Recherche Kali cloud image latest"
  index="$(curl -fsSL "$base/")"
  archive="$(echo "$index" | grep -oE 'kali-linux-[0-9.]+-cloud-genericcloud-amd64\.tar\.xz' | sort -V | tail -n1)"

  [[ -n "${archive:-}" ]] || fail "Impossible de trouver l'archive Kali cloud latest."

  target="$IMAGE_DIR/$archive"
  wget -c "$base/$archive" -O "$target"
  wget -q "$base/SHA256SUMS" -O "$IMAGE_DIR/kali-SHA256SUMS"
  verify_sha256_file "$IMAGE_DIR/kali-SHA256SUMS" "$archive" "$IMAGE_DIR"

  extract_dir="$IMAGE_DIR/kali-cloud-current"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xJf "$target" -C "$extract_dir"

  image_found="$(find "$extract_dir" -type f \( -name '*.qcow2' -o -name '*.img' \) | head -n1)"
  [[ -n "${image_found:-}" ]] || fail "Aucune image .qcow2/.img trouvée dans $archive"

  ln -sf "$image_found" "$IMAGE_DIR/kali-cloud-latest-amd64.img"
  ok "Kali image prête: $image_found"
}

download_ubuntu
download_debian
download_kali

ok "Toutes les images latest sont prêtes."

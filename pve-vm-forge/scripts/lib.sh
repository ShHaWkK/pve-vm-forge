#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config.env"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue() { printf '\033[34m%s\033[0m\n' "$*"; }

fail() {
  red "[x] $*"
  exit 1
}

info() { blue "[i] $*"; }
ok() { green "[+] $*"; }
warn() { yellow "[!] $*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Ce script doit être lancé en root sur le nœud Proxmox."
}

require_config() {
  [[ -f "$CONFIG_FILE" ]] || fail "config.env introuvable. Lance: cp config.example.env config.env puis édite-le."
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Commande manquante: $1"
}

require_proxmox() {
  need_cmd qm
  need_cmd pvesh
  need_cmd pvesm
}

sanitize_name() {
  local value="$1"
  [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{1,62}$ ]] || \
    fail "Nom invalide: $value. Utilise lettres, chiffres, tirets, underscores, points."
}

validate_username() {
  local value="$1"
  [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || \
    fail "Utilisateur invalide: $value. Exemple valide: alex"
}

validate_int() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$label invalide: $value"
}

validate_disk_size() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+[GM]$ ]] || fail "Taille disque invalide: $value. Exemple: 40G"
}

ensure_dirs() {
  mkdir -p "$IMAGE_DIR" "$SNIPPET_DIR"
}

check_storage_exists() {
  local storage="$1"
  pvesm status --storage "$storage" >/dev/null 2>&1 || fail "Stockage Proxmox introuvable: $storage"
}


check_snippet_content_enabled() {
  local storage="$1"
  local content
  content="$(pvesm config "$storage" | awk '/^[[:space:]]*content[[:space:]]/ {print $2; exit}')"
  if [[ -z "$content" || ! ",$content," =~ ,snippets, ]]; then
    fail "Le stockage '$storage' n'autorise pas le contenu 'snippets'. Active-le dans Proxmox: Datacenter > Storage > $storage > Edit > Content > Snippets. En CLI, ajoute 'snippets' au contenu existant avec: pvesm set $storage --content <contenu_existant>,snippets"
  fi
}

check_template_exists() {
  local vmid="$1"
  qm status "$vmid" >/dev/null 2>&1 || fail "Template VMID $vmid introuvable. Lance scripts/build-templates.sh."
}

next_vmid() {
  pvesh get /cluster/nextid
}

hash_password_sha512() {
  local pass="$1"
  need_cmd openssl
  openssl passwd -6 "$pass"
}

resolve_template_var() {
  local var_name="$1"
  local value="${!var_name:-}"
  [[ -n "$value" ]] || fail "Variable de template non définie dans config.env: $var_name"
  echo "$value"
}

get_unused_disk_volume() {
  local vmid="$1"
  qm config "$vmid" | awk -F': ' '/^unused[0-9]+:/ {print $2; exit}'
}

write_cloudinit_snippet() {
  local vmid="$1"
  local hostname="$2"
  local username="$3"
  local pass_hash="$4"
  local preset="$5"
  local file="$SNIPPET_DIR/pve-vm-forge-${vmid}-user.yaml"

  local packages=""
  local runcmd=""

  case "$preset" in
    base)
      packages="
  - qemu-guest-agent
  - openssh-server
  - curl
  - wget
  - git
  - htop
  - tmux
  - vim
  - sudo"
      runcmd="
  - systemctl enable --now qemu-guest-agent || true
  - systemctl enable --now ssh || true"
      ;;
    docker)
      packages="
  - qemu-guest-agent
  - openssh-server
  - curl
  - wget
  - git
  - htop
  - tmux
  - vim
  - sudo
  - ca-certificates
  - docker.io
  - docker-compose-v2"
      runcmd="
  - usermod -aG docker ${username} || true
  - systemctl enable --now qemu-guest-agent || true
  - systemctl enable --now ssh || true
  - systemctl enable --now docker || true"
      ;;
    xfce)
      packages="
  - qemu-guest-agent
  - openssh-server
  - curl
  - wget
  - git
  - htop
  - tmux
  - vim
  - sudo
  - xfce4
  - xfce4-goodies
  - xrdp
  - firefox"
      runcmd="
  - systemctl enable --now qemu-guest-agent || true
  - systemctl enable --now ssh || true
  - systemctl enable --now xrdp || true
  - adduser xrdp ssl-cert || true
  - echo xfce4-session > /home/${username}/.xsession
  - chown ${username}:${username} /home/${username}/.xsession || true"
      ;;
    kali)
      packages="
  - qemu-guest-agent
  - openssh-server
  - curl
  - wget
  - git
  - htop
  - tmux
  - vim
  - sudo"
      runcmd="
  - systemctl enable --now qemu-guest-agent || true
  - systemctl enable --now ssh || true"
      ;;
    *)
      fail "Preset cloud-init inconnu: $preset"
      ;;
  esac

  cat > "$file" <<YAML
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
preserve_hostname: false
ssh_pwauth: true
disable_root: true
package_update: true
package_upgrade: false

users:
  - default
  - name: ${username}
    gecos: ${username}
    shell: /bin/bash
    groups: users,adm,sudo
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: '${pass_hash}'

chpasswd:
  expire: false

packages:${packages}

runcmd:${runcmd}

final_message: "PVE VM Forge: VM prête après cloud-init."
YAML

  chmod 0644 "$file"
  echo "$file"
}

wait_for_cloudinit_hint() {
  cat <<'EOF'

[i] Au premier boot, cloud-init configure l'utilisateur et les paquets.
[i] Dans la VM, tu peux vérifier avec:
    cloud-init status --long

EOF
}

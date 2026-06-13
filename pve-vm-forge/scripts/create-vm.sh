#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_config
require_proxmox
need_cmd awk
need_cmd sed
need_cmd openssl
ensure_dirs
check_storage_exists "$PVE_STORAGE"
check_storage_exists "$SNIPPET_STORAGE"
check_snippet_content_enabled "$SNIPPET_STORAGE"

PROFILES_FILE="$PROJECT_ROOT/profiles/profiles.conf"
[[ -f "$PROFILES_FILE" ]] || fail "Fichier profils introuvable: $PROFILES_FILE"

mapfile -t PROFILES < <(grep -vE '^#|^$' "$PROFILES_FILE")
[[ "${#PROFILES[@]}" -gt 0 ]] || fail "Aucun profil disponible."

echo "========================================"
echo "           PVE VM Forge"
echo "========================================"
echo ""
echo "Profils disponibles:"

idx=1
for line in "${PROFILES[@]}"; do
  IFS='|' read -r key label template_var ram sockets cores disk preset <<< "$line"
  printf "  %d) %s [%s]\n" "$idx" "$label" "$key"
  idx=$((idx + 1))
done

echo ""
read -rp "Choix du profil : " CHOICE
validate_int "Choix" "$CHOICE"
[[ "$CHOICE" -ge 1 && "$CHOICE" -le "${#PROFILES[@]}" ]] || fail "Choix invalide."

SELECTED="${PROFILES[$((CHOICE - 1))]}"
IFS='|' read -r PROFILE_KEY PROFILE_LABEL TEMPLATE_VAR DEFAULT_RAM DEFAULT_SOCKETS DEFAULT_CORES DEFAULT_DISK PRESET <<< "$SELECTED"
TEMPLATE_ID="$(resolve_template_var "$TEMPLATE_VAR")"
check_template_exists "$TEMPLATE_ID"

echo ""
read -rp "Nom de la VM : " VM_NAME
sanitize_name "$VM_NAME"

read -rp "Utilisateur : " VM_USER
validate_username "$VM_USER"

read -rsp "Mot de passe : " VM_PASS
echo ""
[[ -n "$VM_PASS" ]] || fail "Mot de passe vide refusé."

read -rsp "Confirme le mot de passe : " VM_PASS_CONFIRM
echo ""
[[ "$VM_PASS" == "$VM_PASS_CONFIRM" ]] || fail "Les mots de passe ne correspondent pas."

echo ""
echo "Ressources VM. Laisse vide pour les valeurs par défaut."
read -rp "RAM en Mo [$DEFAULT_RAM] : " RAM
RAM="${RAM:-$DEFAULT_RAM}"
validate_int "RAM" "$RAM"

read -rp "Sockets CPU [$DEFAULT_SOCKETS] : " SOCKETS
SOCKETS="${SOCKETS:-$DEFAULT_SOCKETS}"
validate_int "Sockets" "$SOCKETS"

read -rp "Cores par socket [$DEFAULT_CORES] : " CORES
CORES="${CORES:-$DEFAULT_CORES}"
validate_int "Cores" "$CORES"

read -rp "Taille disque [$DEFAULT_DISK] : " DISK_SIZE
DISK_SIZE="${DISK_SIZE:-$DEFAULT_DISK}"
validate_disk_size "$DISK_SIZE"

read -rp "Clone complet ? 0=rapide/lié, 1=full [${DEFAULT_FULL_CLONE}] : " FULL_CLONE
FULL_CLONE="${FULL_CLONE:-$DEFAULT_FULL_CLONE}"
[[ "$FULL_CLONE" == "0" || "$FULL_CLONE" == "1" ]] || fail "Clone complet invalide: $FULL_CLONE"

read -rp "Démarrer la VM après création ? [Y/n] : " START_VM
START_VM="${START_VM:-Y}"

VM_ID="$(next_vmid)"
TOTAL_VCPU=$((SOCKETS * CORES))
PASS_HASH="$(hash_password_sha512 "$VM_PASS")"
SNIPPET_FILE="$(write_cloudinit_snippet "$VM_ID" "$VM_NAME" "$VM_USER" "$PASS_HASH" "$PRESET")"
SNIPPET_BASE="$(basename "$SNIPPET_FILE")"

echo ""
echo "Résumé"
echo "----------------------------------------"
echo "Nom VM        : $VM_NAME"
echo "ID VM         : $VM_ID"
echo "Profil        : $PROFILE_LABEL"
echo "Template      : $TEMPLATE_ID"
echo "Utilisateur   : $VM_USER"
echo "RAM           : ${RAM} Mo"
echo "Sockets       : $SOCKETS"
echo "Cores/socket  : $CORES"
echo "Total vCPU    : $TOTAL_VCPU"
echo "Disque        : $DISK_SIZE"
echo "Clone full    : $FULL_CLONE"
echo "Cloud-init    : ${SNIPPET_STORAGE}:snippets/${SNIPPET_BASE}"
echo "----------------------------------------"
echo ""
read -rp "Créer cette VM ? [y/N] : " CONFIRM
[[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || fail "Création annulée."

ok "Clonage depuis template $TEMPLATE_ID vers VM $VM_ID"
qm clone "$TEMPLATE_ID" "$VM_ID" --name "$VM_NAME" --full "$FULL_CLONE"

ok "Configuration CPU/RAM/cloud-init"
qm set "$VM_ID" \
  --memory "$RAM" \
  --sockets "$SOCKETS" \
  --cores "$CORES" \
  --cpu host \
  --agent enabled=1 \
  --ipconfig0 ip=dhcp \
  --cicustom "user=${SNIPPET_STORAGE}:snippets/${SNIPPET_BASE}"

if [[ -n "${DEFAULT_NAMESERVER:-}" ]]; then
  qm set "$VM_ID" --nameserver "$DEFAULT_NAMESERVER"
fi

if [[ -n "${DEFAULT_SEARCHDOMAIN:-}" ]]; then
  qm set "$VM_ID" --searchdomain "$DEFAULT_SEARCHDOMAIN"
fi

ok "Redimensionnement disque"
qm resize "$VM_ID" scsi0 "$DISK_SIZE" >/dev/null 2>&1 || warn "Redimensionnement ignoré ou impossible. Vérifie le disque dans Proxmox."

qm cloudinit update "$VM_ID" >/dev/null 2>&1 || true

if [[ "$START_VM" =~ ^[Yy]$ ]]; then
  ok "Démarrage VM"
  qm start "$VM_ID"
  wait_for_cloudinit_hint
fi

ok "VM créée."
echo "Nom         : $VM_NAME"
echo "ID          : $VM_ID"
echo "Utilisateur : $VM_USER"
echo "CPU         : ${SOCKETS} socket(s) x ${CORES} core(s) = ${TOTAL_VCPU} vCPU"
echo "RAM         : ${RAM} Mo"
echo "Disque      : $DISK_SIZE"

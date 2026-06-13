#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
require_config
require_proxmox

read -rp "ID de la VM à supprimer : " VM_ID
validate_int "VMID" "$VM_ID"
qm status "$VM_ID" >/dev/null 2>&1 || fail "VMID introuvable: $VM_ID"

qm config "$VM_ID" | sed -n '1,20p'
echo ""
read -rp "Supprimer définitivement VM $VM_ID ? Tape DELETE : " CONFIRM
[[ "$CONFIRM" == "DELETE" ]] || fail "Suppression annulée."

qm stop "$VM_ID" >/dev/null 2>&1 || true
qm destroy "$VM_ID" --purge 1
ok "VM $VM_ID supprimée."

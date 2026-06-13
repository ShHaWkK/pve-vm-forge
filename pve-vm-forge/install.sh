#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f config.env ]]; then
  cp config.example.env config.env
  echo "[+] config.env créé depuis config.example.env"
  echo "[i] Édite config.env avant de lancer les scripts."
else
  echo "[i] config.env existe déjà."
fi

chmod +x scripts/*.sh

echo ""
echo "Commandes:"
echo "  scripts/refresh-images.sh"
echo "  scripts/build-templates.sh"
echo "  scripts/create-vm.sh"

# PVE VM Forge

**PVE VM Forge** est un petit projet Bash pour créer rapidement des VM Proxmox propres depuis des templates cloud-init.

Objectif : créer une VM en quelques minutes en renseignant uniquement :

- le profil de VM ;
- le nom ;
- l'utilisateur ;
- le mot de passe ;
- la RAM ;
- les sockets CPU ;
- les cores par socket ;
- la taille disque.

## Fonctionnement

Le projet fonctionne en deux étapes :

1. **Télécharger les images cloud latest** : Ubuntu, Debian, Kali.
2. **Créer des templates Proxmox** depuis ces images.
3. **Cloner une VM** depuis un template avec cloud-init.

Ce modèle est beaucoup plus rapide qu'une installation ISO complète à chaque VM.

## Profils inclus

| Profil | Base | GUI | Notes |
|---|---|---:|---|
| Ubuntu Server latest | Ubuntu cloud image | Non | Profil serveur propre |
| Debian Server latest | Debian cloud image | Non | Profil serveur minimal |
| Docker Host latest | Ubuntu cloud image | Non | Installe Docker au premier boot |
| Ubuntu XFCE GUI latest | Ubuntu cloud image | Oui | Installe XFCE + XRDP au premier boot |
| Kali Cloud latest | Kali cloud image | Non | Kali cloud rapide avec cloud-init |

> Pour une VM graphique réellement instantanée, crée ensuite une template GUI dédiée déjà préinstallée. Le profil `ubuntu-xfce` fonctionne, mais l'installation de l'interface graphique se fait au premier boot et peut prendre plus longtemps qu'un simple clone serveur.

## Prérequis

Sur le nœud Proxmox :

```bash
apt update
apt install -y curl wget openssl tar grep awk
```

Le projet doit être exécuté en `root` sur le nœud Proxmox.

## Installation

```bash
git clone https://github.com/TON-USER/pve-vm-forge.git
cd pve-vm-forge
./install.sh
nano config.env
```

Dans `config.env`, adapte au minimum :

```bash
PVE_STORAGE="local-lvm"
PVE_BRIDGE="vmbr0"
SNIPPET_STORAGE="local"
SNIPPET_DIR="/var/lib/vz/snippets"
```

Vérifie aussi que le stockage `SNIPPET_STORAGE` accepte le contenu `Snippets` dans Proxmox :

```text
Datacenter > Storage > local > Edit > Content > Snippets
```

## Utilisation complète

### 1. Télécharger les images latest

```bash
scripts/refresh-images.sh
```

### 2. Construire les templates

```bash
scripts/build-templates.sh
```

Cela crée par défaut :

```text
9000 - tmpl-ubuntu-resolute-latest
9001 - tmpl-debian-13-trixie-latest
9002 - tmpl-kali-cloud-latest
```

### 3. Créer une VM

```bash
scripts/create-vm.sh
```

Le script demande :

```text
Profil
Nom de la VM
Utilisateur
Mot de passe
RAM en Mo
Sockets CPU
Cores par socket
Taille disque
Clone lié ou clone complet
Démarrage automatique ou non
```

Exemple de valeurs :

```text
Nom VM       : lab-docker-01
Utilisateur  : alex
RAM          : 4096
Sockets      : 1
Cores/socket : 2
Disque       : 60G
```

## CPU / RAM

Dans Proxmox :

```text
vCPU = sockets × cores
```

Exemples :

```text
1 socket × 2 cores = 2 vCPU
1 socket × 4 cores = 4 vCPU
2 sockets × 2 cores = 4 vCPU
```

Pour la plupart des VM, garde :

```text
Sockets : 1
Cores   : nombre de vCPU voulu
```

Valeurs RAM pratiques :

```text
2048  = 2 Go
4096  = 4 Go
8192  = 8 Go
16384 = 16 Go
32768 = 32 Go
```

## Scripts

```text
scripts/refresh-images.sh   Télécharge Ubuntu/Debian/Kali latest
scripts/build-templates.sh  Crée les templates Proxmox
scripts/create-vm.sh        Crée une VM depuis un template
scripts/list-vms.sh         Liste les VM
scripts/destroy-vm.sh       Supprime une VM proprement
```

## Sécurité

- Le mot de passe est saisi sans affichage.
- Le mot de passe est injecté dans cloud-init sous forme de hash SHA-512.
- Le fichier cloud-init snippet reste sur le nœud Proxmox dans `/var/lib/vz/snippets`.
- Le login SSH par mot de passe est activé pour respecter l'objectif du projet.

Si tu veux durcir ensuite :

- utiliser uniquement des clés SSH ;
- désactiver `ssh_pwauth` ;
- ajouter un réseau isolé par VLAN ;
- ajouter des profils firewall ;
- supprimer automatiquement les snippets après le premier boot.

## Notes importantes

- Les images cloud sont beaucoup plus adaptées que les ISO pour créer des VM rapidement.
- Les ISO latest peuvent servir à reconstruire des templates manuellement, mais installer depuis ISO à chaque création de VM ne donnera pas un résultat en quelques minutes.
- Les profils Docker/XFCE installent des paquets au premier boot via cloud-init. Pour une création vraiment instantanée, transforme ensuite une VM configurée en template dédiée.

## Licence

MIT

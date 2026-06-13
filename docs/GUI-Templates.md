# Templates GUI rapides

Le profil `ubuntu-xfce` installe XFCE au premier boot. Cela fonctionne, mais ce n'est pas le plus rapide.

Pour obtenir une VM GUI en quelques minutes :

1. Crée une VM avec le profil `ubuntu-xfce`.
2. Attends la fin de cloud-init :

```bash
cloud-init status --long
```

3. Nettoie la VM avant conversion en template :

```bash
sudo cloud-init clean --logs
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id
sudo shutdown now
```

4. Depuis le nœud Proxmox :

```bash
qm template <VMID>
```

5. Ajoute cette template dans `config.env` et dans `profiles/profiles.conf`.

Exemple :

```bash
TPL_UBUNTU_XFCE_BAKED="9010"
```

Puis dans `profiles/profiles.conf` :

```text
ubuntu-xfce-baked|Ubuntu XFCE GUI baked|TPL_UBUNTU_XFCE_BAKED|8192|1|4|80G|base
```

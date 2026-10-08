# swam-os-kinoite

Image **bootc** (Fedora Atomic) basée sur **Kinoite officiel**
(`quay.io/fedora-ostree-desktops/kinoite:44`), construite avec
[BlueBuild](https://blue-build.org/). C'est le pendant *kinoite* de
[`swam-os-bazzite`](https://github.com/Swam-web/swam-os-bazzite) : mêmes personnalisations,
socle sans la couche gaming de Bazzite.

- **Base** : `quay.io/fedora-ostree-desktops/kinoite` version `44`
- **Image publiée** : `ghcr.io/swam-web/swam-os-kinoite:latest`

## Personnalisations (tout est fait au build)

| | Détail |
|---|---|
| **Kernel** | CachyOS `kernel-cachyos-lto` (Clang LTO) — COPR `bieszczaders/kernel-cachyos-lto`, remplace le kernel Fedora (pattern `install-kernel-akmods` : shims des scriptlets `kernel-install`, `rpm --erase --nodeps`, versionlock). |
| **NVIDIA open** | dépôt [negativo17](https://negativo17.org/) : `akmod-nvidia` (userland + modules), kmods **recompilés avec clang contre le kernel CachyOS**. |
| **MediaTek MT7927 / MT6639** | modules WiFi + Bluetooth out-of-tree patchés ([`jetm/mediatek-mt7927-dkms`](https://github.com/jetm/mediatek-mt7927-dkms), version épinglée), précompilés contre le kernel CachyOS, installés dans `/usr/lib/modules/<kver>/updates/`, + le blob firmware BT (`BT_RAM_CODE_MT6639_2_1_hdr.bin`) que `linux-firmware` ne fournit pas encore. |
| **Addons CachyOS** | `cachyos-settings`, `scx-scheds`, `scx-tools`, `scx-manager`, `ananicy-cpp`, `cachyos-ananicy-rules`. |
| **Impression / scan / découverte / firewall** | `cups`, `hplip`, `avahi`, `firewalld` (+ `firewall-config`, `firewall-applet`, `tmux`). Services `cups`, `avahi-daemon`, `firewalld`, `podman.socket` activés. |
| **fido2** | module `fido2` ajouté à l'initramfs (déverrouillage LUKS par clé FIDO2). |

## Installation

```bash
sudo bootc switch ghcr.io/swam-web/swam-os-kinoite:latest
sudo systemctl reboot
```

Pour un ISO d'installation : voir « Images disque » plus bas.

## ⚠️ Caveats

- **Secure Boot** : le kernel CachyOS et les modules construits ne sont pas signés par une clé
  approuvée par Microsoft. Désactiver Secure Boot, ou enrôler votre propre clé MOK.
- Le driver **NVIDIA open** supporte **Turing (RTX 20) et plus récent**.
- Le kernel CachyOS est **clang/LTO** : tout kmod tiers doit être recompilé pour cette ABI exacte
  (c'est fait pour NVIDIA et MediaTek dans `files/scripts/`).
- Le build **MT7927** télécharge une tarball `kernel.org` et un ZIP driver depuis le CDN ASUS
  **au moment du build**.
- La base est un **tag flottant Fedora 44** (pas de digest épinglé) : le kernel officiel est de
  toute façon remplacé par celui de CachyOS, et Plasma/les composants suivent les mises à jour
  Fedora.

## Structure du dépôt (BlueBuild)

```
recipes/recipe.yml                       # recette principale (7 modules)
recipes/base/packages.yml                # addons CachyOS, paquets, services
files/scripts/kernel-cachyos.sh          # COPRs + kernel CachyOS clang-LTO
files/scripts/nvidia.sh                  # negativo17 open + kmods rpmbuild clang
files/scripts/mt7927.sh                  # MediaTek MT7927 / MT6639
files/scripts/cleanup.sh                 # nettoyage toolchain / repos de build
files/system/.../99-fido2.conf           # fido2 dans l'initramfs
disk_config/*.toml                       # config bootc-image-builder (ISO / qcow2)
.github/workflows/build.yml              # build + signature de l'image (GHCR)
.github/workflows/build-disk.yml         # build des images disque (bootc-image-builder)
```

> **Important** : chaque module `script` de BlueBuild s'exécute dans un **shell neuf**. Les
> variables partagées dans l'ancien `build.sh` monolithique (typiquement `KERNEL_VERSION`)
> doivent donc être **redéfinies dans chaque script** — sinon `set -u` fait échouer le build.

## Build en local

```bash
cd swam-os-kinoite-bluebuild

# image + ISO en une commande
sudo -E nix run github:blue-build/cli -- generate-iso \
  --iso-name swam-os-kinoite.iso recipe recipes/recipe.yml

# ou juste l'image conteneur (pour tester sans l'ISO)
sudo -E nix run github:blue-build/cli -- build recipe recipes/recipe.yml
```

Validation de la recette seule (rapide, sans build) :

```bash
bluebuild validate recipes/recipe.yml
```

## Images disque (ISO / qcow2)

`disk_config/iso.toml` bascule l'installation sur cette image à la fin :

```
bootc switch --mutate-in-place --transport registry ghcr.io/swam-web/swam-os-kinoite:latest
```

```bash
sudo -E nix run github:blue-build/cli -- generate-iso \
  --iso-name swam-os-kinoite.iso recipe recipes/recipe.yml
```

Ou via GitHub Actions : `Actions → Build disk images → Run workflow` (l'artefact ISO/qcow2 est dans
le résumé du job, ou sur S3 si configuré).

## Signature

Les images sont signées avec **cosign** (clé publique dans `cosign.pub`). La clé privée doit être
dans le secret GitHub **`SIGNING_SECRET`** (clé **non protégée** : `COSIGN_PASSWORD="" cosign
generate-key-pair`). Le module BlueBuild `signing` installe les politiques de vérification pour
`rpm-ostree`/`bootc`.

```bash
cosign verify --key cosign.pub ghcr.io/swam-web/swam-os-kinoite:latest
```

## Images sœurs

- [`swam-os-bazzite`](https://github.com/Swam-web/swam-os-bazzite) — mêmes personnalisations sur
  **Bazzite** (Kinoite + couche gaming), avec en plus les modules manettes Xbox **`xone`** (dongle
  USB) et **`xpadneo`** (Bluetooth).

## Crédits

[Fedora Kinoite](https://fedoraproject.org/kinoite/) / [Universal Blue](https://universal-blue.org/),
[BlueBuild](https://blue-build.org/), [CachyOS](https://cachyos.org/) kernel & addons,
[negativo17](https://negativo17.org/),
[jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms).

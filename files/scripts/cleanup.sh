#!/usr/bin/env bash

# Nettoyage final
set -ouex pipefail

## Kernel modules are prebuilt, remove the build toolchain
dnf5 -y remove kernel-cachyos-lto-devel
dnf5 versionlock delete kernel-cachyos-lto-devel || true

## Do not ship the build repositories enabled on the final image
## (plus aucun dépôt tiers : RPMFusion est la seule pile, elle reste activée)
dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

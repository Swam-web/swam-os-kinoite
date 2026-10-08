#!/usr/bin/env bash

# Nettoyage final
set -ouex pipefail

## Kernel modules are prebuilt, remove the build toolchain
dnf5 -y remove kernel-cachyos-lto-devel
dnf5 versionlock delete kernel-cachyos-lto-devel || true

## Do not ship the build repositories enabled on the final image
rm -f /etc/yum.repos.d/negativo17-fedora-nvidia.repo /etc/yum.repos.d/negativo17-fedora-multimedia.repo
dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

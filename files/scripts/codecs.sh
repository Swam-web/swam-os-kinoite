#!/usr/bin/env bash
#
# Codecs SYSTÈME — pour les applications *natives* (image NVIDIA).
#
# Cette image est bâtie sur la pile **negativo17** (pilote NVIDIA + multimédia).
# RPMFusion n'est PAS utilisé ici : les deux dépôts fournissent les mêmes
# paquets (mesa, libva, ffmpeg…) et les mélanger produit des conflits de
# versions. Règle appliquée : tout vient de negativo17 + Fedora.
#
# Vérifié dans les dépôts au moment de l'écriture :
#   ffmpeg                       8.1.3    [fedora-multimedia]
#   libva (x86_64 ET i686)       2.24.1   [fedora-multimedia]
#   mesa-dri-drivers.i686        26.2.3   [fedora-multimedia]
#   mesa-vulkan-drivers.i686     26.2.3   [fedora-multimedia]
#   gstreamer1-plugins-ugly      1.28.7   [fedora-multimedia]
#   libdvdcss                    1.6.0    [fedora-multimedia]  (pas de dépôt tainted)
#   libva-nvidia-driver(.i686)   0.0.18   [Fedora]
#   gstreamer1-plugins-bad-freeworld et mesa-va-drivers-freeworld sont propres
#   à RPMFusion : ABSENTS ici, donc non utilisés (et inutiles en NVIDIA).
#
# Les codecs des applications FLATPAK sont un autre monde : voir recipes/base/codecs.yml
set -ouex pipefail

### 1. Aucun dépôt à activer : negativo17-nvidia et negativo17-multimedia sont
###    mis en place par nvidia.sh. On vérifie simplement qu'ils sont là.
for r in /etc/yum.repos.d/negativo17-fedora-multimedia.repo \
         /etc/yum.repos.d/negativo17-fedora-nvidia.repo; do
    [[ -f "$r" ]] || { echo "ERREUR : dépôt negativo17 manquant -> $r"; exit 1; }
done

### 2. openh264 vit dans un dépôt Fedora désactivé par défaut
dnf5 config-manager setopt fedora-cisco-openh264.enabled=1

### 3. ffmpeg complet (fedora-multimedia fournit le ffmpeg non bridé)
dnf5 -y swap ffmpeg-free ffmpeg --allowerasing

### 4. Compléments GStreamer (fedora-multimedia)
dnf5 -y install gstreamer1-plugins-ugly gstreamer1-plugin-libav

### 5. H.264 (openh264) + lecture des DVD chiffrés
dnf5 -y install gstreamer1-plugin-openh264 libdvdcss

### 6. Accélération matérielle — NVIDIA
###    Le pilote propriétaire ne fait pas de VA-API nativement : libva-nvidia-driver
###    fait le pont NVDEC/NVENC -> VA-API.
dnf5 -y install libva-nvidia-driver

### 7. Pilotes vidéo 32 bits — requis par Steam pour les jeux 32 bits.
###    Le Flatpak Steam apporte son runtime 32 bits, mais PAS les pilotes de l'hôte.
###    libva est demandé pour les DEUX architectures dans la même transaction :
###    fedora-multimedia les fournit en 2.24.1 identiques, ce qui évite le conflit
###    de fichiers entre le libva.x86_64 de la base et un libva.i686 plus récent.
dnf5 -y install libva libva.i686
dnf5 -y install mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libEGL.i686 vulkan-loader.i686
dnf5 -y install libva-nvidia-driver.i686

### 8. Contrôle : le build échoue plutôt que de livrer une image sans codecs
for p in ffmpeg libdvdcss gstreamer1-plugin-openh264 libva-nvidia-driver \
         libva.i686 mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 \
         libva-nvidia-driver.i686; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "ERREUR : paquet manquant -> $p"; exit 1; }
done
echo "codecs système (nvidia) : OK"

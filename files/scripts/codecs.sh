#!/usr/bin/env bash
#
# Codecs SYSTÈME — pour les applications *natives*
# (Plasma/KWin, Firefox RPM, VLC RPM, Kdenlive, mpv, Elisa…)
#
# RPMFusion uniquement, exactement comme l'image amd : c'est la pile validée.
# Aucun dépôt tiers sur cette image : le pilote comme le multimédia viennent
# de RPMFusion, exactement comme sur l'image amd (une seule pile, zéro conflit).
#
# Toutes les commandes viennent de la doc officielle RPMFusion (Howto/Multimedia).
# Les codecs des applications FLATPAK sont un autre monde : voir recipes/base/codecs.yml
set -ouex pipefail

FEDORA="$(rpm -E %fedora)"

### 1. Dépôts RPMFusion : free + nonfree (URLs officielles de la doc).
###    Idempotent : nvidia.sh les a déjà posés.
dnf5 -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

### 1b. Dépôt tainted (nécessaire pour libdvdcss) : par NOM de paquet.
###     Il n'existe PAS d'URL « -release-tainted » dans free/ (404 vérifié en
###     build) ; le paquet est fourni par rpmfusion-free, activé juste au-dessus.
###     C'est la procédure exacte de la doc RPMFusion.
dnf5 -y install rpmfusion-free-release-tainted

### 2. openh264 vit dans un dépôt Fedora désactivé par défaut
dnf5 config-manager setopt fedora-cisco-openh264.enabled=1

### 3. ffmpeg complet (remplace le ffmpeg-free privé des codecs brevetés).
###    Après ce swap, libavcodec-freeworld est inutile et redondant (doc RPMFusion).
dnf5 -y swap ffmpeg-free ffmpeg --allowerasing

### 4. Compléments multimédia / GStreamer (commande officielle RPMFusion)
dnf5 -y install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

### 5. H.264 (openh264) + lecture des DVD chiffrés
dnf5 -y install gstreamer1-plugin-openh264 libdvdcss

### 6. Accélération matérielle — NVIDIA
###    Le pilote propriétaire ne fait pas de VA-API nativement : libva-nvidia-driver
###    fait le pont NVDEC/NVENC -> VA-API (paquet Fedora, aucun conflit possible).
dnf5 -y install libva-nvidia-driver

### 7. Pilotes vidéo 32 bits — requis par Steam pour les jeux 32 bits.
###    Le Flatpak Steam apporte son propre runtime 32 bits, mais PAS les pilotes
###    de l'hôte : sans ça, ni Vulkan ni GL ni VA-API en 32 bits.
dnf5 -y install mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 vulkan-loader.i686 libva.i686
dnf5 -y install libva-nvidia-driver.i686

### 8. Contrôle : le build échoue plutôt que de livrer une image sans codecs
###    libva.i686 est vérifié explicitement : c'est le paquet qui a cassé deux
###    fois (conflit de fichiers quand une version 2.24.1 epoch-1 coexiste avec
###    le 2.23.0 du x86_64). Sans dépôt tiers, les deux arches restent en 2.23.0.
for p in ffmpeg libdvdcss gstreamer1-plugin-openh264 libva-nvidia-driver \
         libva-nvidia-driver.i686 mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 \
         libva.i686; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "ERREUR : paquet manquant -> $p"; exit 1; }
done
echo "codecs système (nvidia, RPMFusion) : OK"

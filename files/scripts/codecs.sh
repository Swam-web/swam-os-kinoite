#!/usr/bin/env bash
#
# Codecs SYSTÈME — pour les applications *natives*
# (Plasma/KWin, Firefox RPM, VLC RPM, Kdenlive, mpv, Elisa…)
#
# Kinoite n'active pas RPMFusion : sans ces paquets, pas de lecture H.264/H.265,
# pas d'accélération matérielle, pas de DVD chiffré.
# Les codecs des applications FLATPAK sont un autre monde : voir recipes/base/codecs.yml
#
# Toutes les commandes ci-dessous viennent de la doc officielle RPMFusion
# (Howto/Multimedia), pas d'invention.
set -ouex pipefail

FEDORA="$(rpm -E %fedora)"

### 1. Dépôts RPMFusion : free + nonfree (URLs officielles de la doc)
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
###    fait le pont NVDEC/NVENC -> VA-API (doc RPMFusion).
dnf5 -y install libva-nvidia-driver
#
# Si la machine a AUSSI un iGPU AMD/Intel, décommente :
# dnf5 -y install mesa-va-drivers-freeworld
# dnf5 -y swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld

### 7. Pilotes vidéo 32 bits — requis par Steam pour les jeux 32 bits.
###    Le Flatpak Steam apporte son runtime 32 bits, mais PAS les pilotes de l'hôte.
dnf5 -y install mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 vulkan-loader.i686 libva.i686
dnf5 -y install libva-nvidia-driver.i686

### 8. Contrôle : le build échoue plutôt que de livrer une image sans codecs
for p in ffmpeg libdvdcss gstreamer1-plugin-openh264 libva-nvidia-driver \
         mesa-dri-drivers.i686 mesa-vulkan-drivers.i686; do
    rpm -q "$p" >/dev/null 2>&1 || { echo "ERREUR : paquet manquant -> $p"; exit 1; }
done
echo "codecs système : OK"

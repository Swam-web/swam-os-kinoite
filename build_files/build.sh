#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Enable COPRs (CachyOS kernel + addons)
dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons

### Enable the negativo17 NVIDIA repository (open drivers)
cat > /etc/yum.repos.d/negativo17-fedora-nvidia.repo <<'EOF'
[fedora-nvidia]
name=negativo17 - Nvidia
baseurl=https://negativo17.org/repos/nvidia/fedora-$releasever/$basearch/
enabled=1
skip_if_unavailable=1
gpgcheck=1
gpgkey=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
enabled_metadata=1
metadata_expire=6h
type=rpm-md
repo_gpgcheck=0
EOF

### Exclude the RPMFusion NVIDIA packages permanently
## The negativo17 and RPMFusion NVIDIA stacks are mutually exclusive:
## RPMFusion stays enabled for everything else, but its NVIDIA packages
## can no longer be selected over the ones installed from negativo17.
for repo in rpmfusion-nonfree.repo rpmfusion-nonfree-updates.repo; do
    if [[ -f "/etc/yum.repos.d/${repo}" ]]; then
        if ! grep -q "^exclude=" "/etc/yum.repos.d/${repo}"; then
            sed -i '/^\[rpmfusion-nonfree]$/a exclude=akmod-nvidia kmod-nvidia* nvidia-* libnvidia-* xorg-x11-nvidia xorg-x11-drv-nvidia*' "/etc/yum.repos.d/${repo}"
        fi
    fi
done

### CachyOS kernel (clang LTO) replacing the stock Fedora kernel
## Shim the kernel-install scriptlets so dracut/rpm-ostree are not triggered
## during the build, following the Bazzite install-kernel-akmods pattern.
pushd /usr/lib/kernel/install.d
for script in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${script}" ]]; then
        mv "${script}" "${script}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "${script}"
        chmod +x "${script}"
    fi
done
popd

## Remove the stock kernel and the kmods that were built for it
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        rpm --erase "${pkg}" --nodeps
    fi
done
mapfile -t STOCK_KMODS < <(rpm -qa --qf '%{NAME}\n' | grep -E '^(kmod-|openrazer)' | grep -vE '^kmod-libs$' || true)
for pkg in "${STOCK_KMODS[@]}"; do
    rpm --erase "${pkg}" --nodeps
done
rm -rf /usr/lib/modules

## Remove the versionlock entries the base image left for the stock kernel
dnf5 versionlock delete kernel kernel-devel kernel-devel-matched kernel-core kernel-modules || true

## Install the CachyOS kernel and its headers
## (devel pulls clang/lld/make and provides kernel-devel-uname-r for module builds)
dnf5 -y install kernel-cachyos-lto kernel-cachyos-lto-devel

## Lock the kernel packages so nothing replaces them during the rest of the build
dnf5 versionlock add kernel-cachyos-lto kernel-cachyos-lto-devel

KERNEL_VERSION="$(rpm -q kernel-cachyos-lto --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
echo "CachyOS kernel: ${KERNEL_VERSION}"

## Restore the kernel-install scriptlets
pushd /usr/lib/kernel/install.d
for script in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${script}.bak" ]]; then
        mv -f "${script}.bak" "${script}"
    fi
done
popd

### NVIDIA open drivers (negativo17), kernel modules built with clang against the CachyOS kernel
## Disable RPMFusion so it does not compete with the negativo17 akmod-nvidia
for repo in rpmfusion-free.repo rpmfusion-free-updates.repo rpmfusion-nonfree.repo rpmfusion-nonfree-updates.repo; do
    if [[ -f "/etc/yum.repos.d/${repo}" ]]; then
        sed -i 's/enabled=1/enabled=0/' "/etc/yum.repos.d/${repo}"
    fi
done

## Install the akmods tool first (required by the akmod-nvidia dependency check)
dnf5 -y install akmods

## Install akmod-nvidia WITHOUT its %post scriptlet: the scriptlet
## (akmods-ostree-post) runs akmodsbuild directly as root, which refuses
## when /var is writable and aborts the whole RPM transaction. Installing
## it first with --noscripts still registers its Provides (nvidia-kmod,
## nvidia-kmod-common...), so the userland install below does not pull it
## back in with its failing %post.
DRIVER_VERSION="$(dnf5 repoquery --qf '%{VERSION}-%{RELEASE}\n' akmod-nvidia | sort -V | tail -n1)"
dnf5 -y download --destdir /tmp/nvidia-rpms "akmod-nvidia-${DRIVER_VERSION}"
## --noscripts skips the failing %post, --nodeps skips the versioned
## dependency check (nvidia-kmod-common is installed just after)
rpm -i --noscripts --nodeps /tmp/nvidia-rpms/akmod-nvidia-*.rpm
rm -rf /tmp/nvidia-rpms

## Enable the negativo17 multimedia repo: the Bazzite base excludes the
## Fedora mesa i686 packages, and the 32-bit nvidia libraries need them
## (same as the ublue nvidia-install.sh)
cat > /etc/yum.repos.d/negativo17-fedora-multimedia.repo <<'EOF'
[fedora-multimedia]
name=negativo17 - Multimedia
baseurl=https://negativo17.org/repos/multimedia/fedora-$releasever/$basearch/
enabled=1
skip_if_unavailable=1
gpgkey=https://negativo17.org/repos/RPM-GPG-KEY-slaanesh
gpgcheck=1
enabled_metadata=1
metadata_expire=6h
type=rpm-md
repo_gpgcheck=0
EOF
## The base versionlocks the mesa packages (protecting its terra mesa), but
## mesa-libEGL.i686 is locked to a terra version that is not available in
## the base repos and is not installed. Remove the mesa locks entirely, then
## install it from negativo17-multimedia (needed by the 32-bit nvidia libs),
## and re-lock only the kernel.
dnf5 versionlock list || true
dnf5 versionlock delete mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm mesa-vulkan-drivers xorg-x11-server-Xwayland || true
dnf5 versionlock clear || true
dnf5 versionlock add kernel-cachyos-lto kernel-cachyos-lto-devel || true
dnf5 -y install mesa-libEGL.i686

## Install the userland stack (the i686 libraries are needed for 32-bit
## games through Steam on NVIDIA)
dnf5 -y install \
    nvidia-driver \
    nvidia-driver-cuda \
    nvidia-driver-cuda-libs \
    nvidia-driver-libs \
    nvidia-driver-libs.i686 \
    nvidia-driver-cuda-libs.i686 \
    nvidia-driver-common.i686 \
    libnvidia-fbc.i686 \
    nvidia-kmod-common \
    nvidia-modprobe \
    nvidia-persistenced \
    nvidia-settings \
    nvidia-libXNVCtrl \
    xorg-x11-nvidia \
    nvidia-xconfig

## Same post-install adjustments as the ublue nvidia images
rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
if [[ -f /usr/lib/dracut/dracut.conf.d/99-nvidia.conf ]]; then
    sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
    sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
fi
systemctl enable nvidia-persistenced.service

## Build the nvidia kernel modules directly with rpmbuild as root: the
## akmodsbuild wrapper refuses root (its [[ -w /var ]] check) and the akmods
## runuser drop fails in containers (PAM session). The akmod SRPM ships the
## spec and the open-gpu-kernel-modules source, the kmodtool spec builds the
## per-kernel RPM. Clang env because the CachyOS kernel is clang/LTO.
## rpmbuild does not create its tree itself (the cpio unpack of the SRPM
## fails without it), so create a dedicated topdir first
NVIDIA_BUILD="/tmp/nvidia-build"
mkdir -p "${NVIDIA_BUILD}"/{BUILD,SOURCES,SPECS,SRPMS,RPMS}

export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
rpmbuild --rebuild --define "_topdir ${NVIDIA_BUILD}" --define "kernels ${KERNEL_VERSION}" /usr/src/akmods/nvidia-kmod.latest
unset CC CXX LD LLVM LLVM_IAS

find "${NVIDIA_BUILD}/RPMS" -type f -name '*.rpm' ! -name '*debuginfo*' -exec rpm -i {} \;
rm -rf "${NVIDIA_BUILD}"
depmod -a "${KERNEL_VERSION}"

## Re-enable RPMFusion
for repo in rpmfusion-free.repo rpmfusion-free-updates.repo rpmfusion-nonfree.repo rpmfusion-nonfree-updates.repo; do
    if [[ -f "/etc/yum.repos.d/${repo}" ]]; then
        sed -i 's/enabled=0/enabled=1/' "/etc/yum.repos.d/${repo}"
    fi
done

## Remove the terra repo files shipped by the base: terra-mesa references a
## file:// GPG key that is absent from the image, which breaks the depsolve
## inside the bootc-image-builder when building disk images
rm -f /etc/yum.repos.d/*terra* /etc/dnf/dnf5/repos.d/*terra* /usr/share/dnf5/repos.d/*terra*

NVIDIA_KO="$(find /usr/lib/modules/"${KERNEL_VERSION}" -name 'nvidia.ko*' -print -quit)"
if [[ -z "${NVIDIA_KO}" ]]; then
    cat /var/cache/akmods/nvidia/*.failed.log
    exit 1
fi

### MediaTek MT7927 WiFi + MT6639 Bluetooth
## Out-of-tree patched modules from jetm/mediatek-mt7927-dkms, prebuilt
## in the image against the CachyOS kernel (dkms does not work on bootc).
dnf5 -y install patch

MT7927_VERSION="2.16-1"
MT7927_DIR="$(mktemp -d /tmp/mt7927-XXXXXXXX)"
curl -sL -f -o "${MT7927_DIR}/src.tar.gz" \
    "https://github.com/jetm/mediatek-mt7927-dkms/archive/refs/tags/v${MT7927_VERSION}.tar.gz"
tar -xzf "${MT7927_DIR}/src.tar.gz" -C "${MT7927_DIR}" --strip-components=1

make -C "${MT7927_DIR}" download
make -C "${MT7927_DIR}" sources

## Build with clang (the CachyOS kernel is clang/LTO)
export CC=clang CXX=clang++ LD=ld.lld LLVM=1 LLVM_IAS=1
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/mt76" modules
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/bluetooth" modules
unset CC CXX LD LLVM LLVM_IAS

## Install the modules (updates/ shadows the in-tree ones)
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/mt76" modules_install INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="${MT7927_DIR}/_build/bluetooth" modules_install INSTALL_MOD_PATH= INSTALL_MOD_DIR=updates

MT7925_KO="$(find /usr/lib/modules/"${KERNEL_VERSION}"/updates -name 'mt7925e.ko*' -print -quit)"
if [[ -z "${MT7925_KO}" ]]; then
    exit 1
fi
depmod -a "${KERNEL_VERSION}"

## Bluetooth firmware blob (ours to ship: linux-firmware does not have it yet)
install -Dm644 "${MT7927_DIR}/_build/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin" \
    /usr/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin

rm -rf "${MT7927_DIR}"

### Generate the initramfs for the CachyOS kernel
QUALIFIED_KERNEL="$(dnf5 repoquery --installed --queryformat='%{evr}.%{arch}' kernel-cachyos-lto)"
/usr/bin/dracut --no-hostonly --kver "${QUALIFIED_KERNEL}" --reproducible --zstd -v --add ostree --add fido2 -f "/usr/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"
chmod 0600 /usr/lib/modules/"${QUALIFIED_KERNEL}"/initramfs.img

### CachyOS addons
## Kinoite may not ship scx-scheds/scx-tools: they are installed from the
## COPR when missing (no-op otherwise). cachyos-settings provides its own
## zram-generator-defaults, conflicting with the base one — --allowerasing
## swaps it for the CachyOS version.
dnf5 -y install --allowerasing \
    cachyos-settings \
    scx-scheds \
    scx-tools \
    scx-manager \
    ananicy-cpp \
    cachyos-ananicy-rules

### Install packages
## Printing, scanning, discovery and firewall (no-op if already in the base image)
dnf5 install -y \
    firewalld \
    firewall-config \
    firewall-applet \
    hplip \
    cups \
    avahi \
    tmux

## Enable the services (no-op if already enabled by the base image)
systemctl enable cups.service
systemctl enable avahi-daemon.service
systemctl enable avahi-daemon.socket
systemctl enable firewalld.service
systemctl enable podman.socket

### Cleanup
## Kernel modules are prebuilt, remove the build toolchain
dnf5 -y remove kernel-cachyos-lto-devel
dnf5 versionlock delete kernel-cachyos-lto-devel || true

## Do not ship the build repositories enabled on the final image
rm -f /etc/yum.repos.d/negativo17-fedora-nvidia.repo /etc/yum.repos.d/negativo17-fedora-multimedia.repo
dnf5 -y copr disable bieszczaders/kernel-cachyos-lto
dnf5 -y copr disable bieszczaders/kernel-cachyos-addons

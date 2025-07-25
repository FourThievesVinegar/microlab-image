#!/usr/bin/env bash
set -euo pipefail

# Ensure the script is running as root (or via sudo)
if [ "$(id -u)" -ne 0 ]; then
  echo >&2 "ERROR: This script must be run as root. Try:"
  echo >&2 "  sudo $0 $*"
  exit 1
fi

# --- VARIABLES ---
# assume we started in /workspace
WORKDIR="$(pwd)"
BUILD_DIR="$WORKDIR/build"

MNT_DIR="$BUILD_DIR/mnt"
BASE_IMG_XZ="$BUILD_DIR/raspios-lite.img.xz"
OUTPUT_IMG="$BUILD_DIR/raspios-microlab.img"
RASPBIAN_URL="https://downloads.raspberrypi.org/raspios_lite_armhf_latest"
MICROLAB_TAG="${1:-main}" # Use the first argument as the tag, default to "main"

# 1. Prepare
mkdir -p "$BUILD_DIR"
if [ -f "$BASE_IMG_XZ" ]; then
  echo "==> Using cached OS image: $BASE_IMG_XZ"
else
  echo "==> Downloading Raspberry Pi OS Lite..."
  curl -L "$RASPBIAN_URL" -o "$BASE_IMG_XZ"
fi

echo "==> Decompressing .img.xz archive…"
# requires xz-utils in the builder image
xz --decompress --keep --force --verbose "$BASE_IMG_XZ"
BASE_IMG_RAW="${BASE_IMG_XZ%.img.xz}.img"

# 2. Setup loop devices & mount
echo "==> Setting up loop device"
LOOPDEV=$(losetup --show -f "$BASE_IMG_RAW")

# ensure the kernel sees the partitions
echo "==> Creating partition mappings with kpartx"
kpartx -a "$LOOPDEV"

# `${LOOPDEV##*/}` is e.g. "loop3"
DEV_NAME=$(basename "$LOOPDEV")
BOOT_PART="/dev/mapper/${DEV_NAME}p1"
ROOT_PART="/dev/mapper/${DEV_NAME}p2"


# ensure our mount dirs exist
mkdir -p "$MNT_DIR/boot" "$MNT_DIR/root"

# mount the Pi's boot and root partitions
mount "$BOOT_PART" "$MNT_DIR/boot"
mount "$ROOT_PART" "$MNT_DIR/root"

# 3. Apply overlays
echo "==> Applying bootloader configs..."
cp -r "$WORKDIR/config/"* "$MNT_DIR/boot/"

echo "==> Overlaying root filesystem..."
cp -r "$WORKDIR/overlays/rootfs-overlay/"* "$MNT_DIR/root"

# 4. Chroot + provisioning
echo "==> Copying QEMU and provisioning script..."
mkdir -p "$MNT_DIR/root/usr/bin"
mkdir -p "$MNT_DIR/root/tmp"

cp /usr/bin/qemu-arm-static "$MNT_DIR/root/usr/bin/"
cp "$WORKDIR/scripts/configure-microlab.sh" "$MNT_DIR/root/tmp/"

echo "==> Entering chroot to provision image..."
chroot "$MNT_DIR/root" /bin/bash -lc "bash /tmp/configure-microlab.sh $MICROLAB_TAG"

# 5. Teardown
echo "==> Cleaning up mounts"
umount "$MNT_DIR/boot" "$MNT_DIR/root"
echo "==> Removing partition mappings"
kpartx -d "$LOOPDEV"
losetup -d "$LOOPDEV"

# 6. Finalize
mv "$BASE_IMG_RAW" "$OUTPUT_IMG"
echo "==> Built image at: $OUTPUT_IMG"

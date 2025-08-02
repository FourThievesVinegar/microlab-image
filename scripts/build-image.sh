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

echo "==> Expanding image file to 6 GiB"
truncate -s 6G "$BASE_IMG_RAW"

# 2. Setup loop devices & mount
echo "==> Setting up loop device"
LOOPDEV=$(losetup --show -f "$BASE_IMG_RAW")

echo "==> Resizing partition 2 to fill the expanded image"
parted --script "$LOOPDEV" resizepart 2 100%

# ensure the kernel sees the partitions
echo "==> Creating partition mappings with kpartx"
kpartx -a "$LOOPDEV"

# `${LOOPDEV##*/}` is e.g. "loop3"
DEV_NAME=$(basename "$LOOPDEV")
BOOT_PART="/dev/mapper/${DEV_NAME}p1"
ROOT_PART="/dev/mapper/${DEV_NAME}p2"

# 3. Resize the root filesystem to fill the partition**
echo "==> Checking filesystem on $ROOT_PART"
e2fsck -f -p "$ROOT_PART"

echo "==> Resizing $ROOT_PART to use all available space"
resize2fs "$ROOT_PART"

# 4. Mount Raspberry Pi boot and root partitions
echo "==> Mounting Raspberry Pi boot and root partitions..."
mkdir -p "$MNT_DIR/boot" "$MNT_DIR/root"
mount "$BOOT_PART" "$MNT_DIR/boot"
mount "$ROOT_PART" "$MNT_DIR/root"

# 5. Apply overlays
echo "==> Applying bootloader configs..."
cp -r "$WORKDIR/config/"* "$MNT_DIR/boot/"

echo "==> Overlaying root filesystem..."
cp -r "$WORKDIR/overlays/rootfs-overlay/"* "$MNT_DIR/root"

# 6. Chroot + provisioning
echo "==> Copying QEMU and provisioning script..."
mkdir -p "$MNT_DIR/root/usr/bin"
mkdir -p "$MNT_DIR/root/tmp"

cp /usr/bin/qemu-arm-static "$MNT_DIR/root/usr/bin/"
cp "$WORKDIR/scripts/configure-microlab.sh" "$MNT_DIR/root/tmp/"
cp "$WORKDIR/scripts/install-venv.sh"  "$MNT_DIR/root/tmp/"
cp "$WORKDIR/scripts/install-node-yarn.sh"  "$MNT_DIR/root/tmp/"
cp "$WORKDIR/scripts/compile-ui.sh"  "$MNT_DIR/root/tmp/"

COPY --chmod=0755 inspect-image.sh /opt/inspect-image.sh

echo "==> Entering chroot to provision image..."
chroot "$MNT_DIR/root" /bin/bash -lc "bash /tmp/configure-microlab.sh $MICROLAB_TAG"

# 7. Teardown
echo "==> Cleaning up mounts"
umount "$MNT_DIR/boot" "$MNT_DIR/root"
echo "==> Removing partition mappings"
kpartx -d "$LOOPDEV"
losetup -d "$LOOPDEV"

# 8. Finalize
mv "$BASE_IMG_RAW" "$OUTPUT_IMG"
echo "==> Built image at: $OUTPUT_IMG"

#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <path-to-raspios-image>"
  exit 1
fi

IMG="$1"
LOOP_DEV=""
MAPPER_PREFIX="loop0"

cleanup() {
  echo "Cleaning up..."
  mountpoint -q /mnt/pi-boot && umount /mnt/pi-boot
  mountpoint -q /mnt/pi-root && umount /mnt/pi-root
  if [ -n "$LOOP_DEV" ]; then
    kpartx -d "$LOOP_DEV" || true
    losetup -d "$LOOP_DEV" || true
  fi
}
trap cleanup EXIT

echo "Associating '$IMG' with a loop device..."
LOOP_DEV=$(losetup --show -f "$IMG")
echo "  -> $LOOP_DEV"

echo "Creating partition mappings..."
kpartx -av "$LOOP_DEV"

echo "Mounting partitions..."
mkdir -p /mnt/pi-boot /mnt/pi-root

mount "/dev/mapper/${MAPPER_PREFIX}p1" /mnt/pi-boot
echo "  • Boot partition: /mnt/pi-boot"

mount "/dev/mapper/${MAPPER_PREFIX}p2" /mnt/pi-root
echo "  • Rootfs partition: /mnt/pi-root"

cat <<-EOF

=== INSPECTION READY ===
  • Browse boot:  ls /mnt/pi-boot
  • Browse root:  ls /mnt/pi-root

Exit the shell when done to auto-cleanup.
EOF

exec /bin/bash --login

#!/bin/bash
# Flash a complete SD card for the Lichee Pi Nano: U-Boot + kernel + DTB +
# boot script + root filesystem.
#
#   ./scripts/flash-sd.sh /dev/sdX
#
# THIS ERASES THE TARGET DEVICE. It refuses to touch anything that is not a
# removable disk, and asks before writing.
#
# Run ./scripts/build-uboot.sh and ./scripts/build-kernel.sh first.
set -e

cd "$(dirname "$0")/.."

ASSUME_YES=0
for a in "$@"; do
	case "$a" in
	-y | --yes) ASSUME_YES=1 ;;
	esac
done
set -- $(printf '%s\n' "$@" | grep -vE '^(-y|--yes)$' || true)

DEV="$1"
if [ -z "$DEV" ]; then
	echo "usage: $0 /dev/sdX" >&2
	echo >&2
	echo "removable disks currently attached:" >&2
	lsblk -d -o NAME,SIZE,RM,MODEL | awk 'NR==1 || $3==1' | sed 's/^/  /' >&2
	exit 1
fi

# ---- safety checks -------------------------------------------------------
[ -b "$DEV" ] || { echo "error: $DEV is not a block device" >&2; exit 1; }

BASE=$(basename "$(readlink -f "$DEV")")
if [ "$(cat "/sys/block/$BASE/removable" 2>/dev/null)" != "1" ]; then
	echo "error: $DEV is not a removable disk -- refusing." >&2
	echo "       (this is the check that stops you erasing your laptop's disk)" >&2
	exit 1
fi

ROOTDEV=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)
if [ -n "$ROOTDEV" ] && [ "$ROOTDEV" = "$BASE" ]; then
	echo "error: $DEV holds your running root filesystem -- refusing." >&2
	exit 1
fi

# sdX -> sdX1 ; mmcblkX / nvmeX -> mmcblkXp1
case "$DEV" in
*[0-9]) PART="${DEV}p" ;;
*)      PART="${DEV}" ;;
esac

# ---- inputs --------------------------------------------------------------
ROOTFS=files/core-image-minimal-f1c100s.rootfs.tar.xz
for f in output/u-boot-sunxi-with-spl.bin output/zImage \
         output/suniv-f1c100s-licheepi-nano.dtb "$ROOTFS"; do
	[ -f "$f" ] || { echo "error: missing $f" >&2
	                 echo "       run ./scripts/build-uboot.sh and ./scripts/build-kernel.sh" >&2
	                 exit 1; }
done

if [ ! -f output/boot.scr ]; then
	echo "==> generating boot.scr"
	mkimage -C none -A arm -T script -d files/boot.cmd output/boot.scr >/dev/null
fi

# ---- confirm -------------------------------------------------------------
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL "$DEV"
echo
echo "ALL DATA ON $DEV WILL BE ERASED."
if [ "$ASSUME_YES" = "1" ]; then
	echo "(--yes given, continuing without prompting)"
else
	printf "Type YES to continue: "
	read -r ANSWER
	[ "$ANSWER" = "YES" ] || { echo "aborted."; exit 1; }
fi

# ---- write ---------------------------------------------------------------
echo "==> unmounting any mounted partitions"
for p in "${PART}"*; do [ -b "$p" ] && sudo umount "$p" 2>/dev/null || true; done

echo "==> partitioning (128MiB FAT boot + ext4 rootfs)"
printf 'label: dos\nstart=2048, size=128MiB, type=b\nstart=264192, type=83\n' \
	| sudo sfdisk "$DEV" >/dev/null
sudo partprobe "$DEV" 2>/dev/null || true
sleep 2

# U-Boot lives in raw sectors 16..624, below the 1MiB where partition 1 starts.
# It must be written after partitioning (sfdisk rewrites the first sector) but
# before mkfs, and never as a file on a filesystem.
echo "==> writing U-Boot to raw sectors (seek=8k)"
sudo dd if=output/u-boot-sunxi-with-spl.bin of="$DEV" bs=1k seek=8 conv=notrunc status=none
sync

echo "==> formatting"
sudo mkfs.vfat -n boot   "${PART}1" >/dev/null
sudo mkfs.ext4 -q -L rootfs "${PART}2"

MNT=$(mktemp -d)
echo "==> copying kernel, dtb and boot script"
sudo mount "${PART}1" "$MNT"
sudo cp output/zImage output/suniv-f1c100s-licheepi-nano.dtb output/boot.scr "$MNT"/
sudo umount "$MNT"

echo "==> unpacking root filesystem (this takes a minute)"
sudo mount "${PART}2" "$MNT"
sudo tar xpf "$ROOTFS" -C "$MNT"
sync
sudo umount "$MNT"
rmdir "$MNT"
sync

echo
echo "Done. $DEV is ready -- put it in the board and power on."
echo "  serial: 115200 8N1 on PE0/PE1     login: root (no password)"
echo "  adb:    adb devices  ->  embeddedlinux.blog"

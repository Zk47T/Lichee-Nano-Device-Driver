#!/bin/bash
# Build the kernel (zImage + dtb) for the Lichee Pi Nano.
#
#   ./scripts/build-kernel.sh
#
# Outputs: output/zImage
#          output/suniv-f1c100s-licheepi-nano.dtb
#
# Both go on the SD card's FAT boot partition.
set -e

cd "$(dirname "$0")/.."

ARCH=arm
CROSS_COMPILE=arm-linux-gnueabi-
export ARCH CROSS_COMPILE

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
	echo "error: ${CROSS_COMPILE}gcc not found." >&2
	echo "       sudo apt install gcc-arm-linux-gnueabi" >&2
	exit 1
fi

if [ ! -f linux/Makefile ]; then
	echo "error: linux/ is empty -- the submodule was not checked out." >&2
	echo "       git submodule update --init" >&2
	exit 1
fi

mkdir -p output

# Board customisations live in this repo so the submodule stays a clean
# checkout of the fork:
#   f1c100s_defconfig  - adds the USB gadget stack (adb) on top of the fork's config
#   ...licheepi-nano.dts - sets dr_mode = "peripheral" so the gadget enumerates
echo "==> installing board config + DTS"
cp files/f1c100s_defconfig                 linux/arch/arm/configs/
cp files/suniv-f1c100s-licheepi-nano.dts   linux/arch/arm/boot/dts/

echo "==> configuring kernel"
make -C linux f1c100s_defconfig >/dev/null

echo "==> building zImage + dtb (this takes a few minutes)"
make -C linux -j"$(nproc)" zImage suniv-f1c100s-licheepi-nano.dtb

cp linux/arch/arm/boot/zImage                                  output/
cp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb     output/

echo
echo "Done:"
echo "  output/zImage                            ($(wc -c < output/zImage) bytes)"
echo "  output/suniv-f1c100s-licheepi-nano.dtb   ($(wc -c < output/suniv-f1c100s-licheepi-nano.dtb) bytes)"
echo
echo "Sanity check - the USB gadget options adb needs:"
grep -cE "^CONFIG_(USB_GADGET|USB_CONFIGFS|USB_CONFIGFS_F_FS|CONFIGFS_FS|USB_LIBCOMPOSITE|USB_MUSB_DUAL_ROLE)=y" linux/.config \
	| sed 's/^/  /;s/$/ of 6 present (expect 6)/'

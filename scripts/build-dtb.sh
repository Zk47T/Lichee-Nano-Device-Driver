#!/bin/bash
# Build the device tree blob for the Lichee Pi Nano.
#
#   ./scripts/build-dtb.sh
#
# Output: output/suniv-f1c100s-licheepi-nano.dtb  (copy this to the SD card's
# FAT boot partition)
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

# Board customisations live in this repo, not the submodule, so the submodule
# stays a clean checkout of the fork. dr_mode is set to "peripheral" here --
# see the comment in the file.
echo "==> installing board DTS"
cp files/suniv-f1c100s-licheepi-nano.dts linux/arch/arm/boot/dts/

# A DTB target needs a configured tree (it reads include/config/auto.conf).
echo "==> configuring kernel"
make -C linux f1c100s_defconfig >/dev/null

echo "==> building dtb"
make -C linux -j"$(nproc)" suniv-f1c100s-licheepi-nano.dtb

cp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb output/
echo
echo "Done: output/suniv-f1c100s-licheepi-nano.dtb ($(wc -c < output/suniv-f1c100s-licheepi-nano.dtb) bytes)"

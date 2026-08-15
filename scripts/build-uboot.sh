#!/bin/bash
# Build U-Boot (SPL + U-Boot proper) for the Lichee Pi Nano.
#
#   ./scripts/build-uboot.sh
#
# Output: output/u-boot-sunxi-with-spl.bin
#
# This is written to RAW SECTORS of the SD card (not a file on a partition):
#   sudo dd if=output/u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1k seek=8 conv=notrunc
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

if [ ! -f u-boot-f1c100s/Makefile ]; then
	echo "error: u-boot-f1c100s/ is empty -- the submodule was not checked out." >&2
	echo "       git submodule update --init" >&2
	exit 1
fi

mkdir -p output

echo "==> configuring u-boot"
make -C u-boot-f1c100s licheepi_nano_defconfig >/dev/null

echo "==> building u-boot"
make -C u-boot-f1c100s -j"$(nproc)" PYTHON=python3

cp u-boot-f1c100s/u-boot-sunxi-with-spl.bin output/

echo
echo "Done: output/u-boot-sunxi-with-spl.bin ($(wc -c < output/u-boot-sunxi-with-spl.bin) bytes)"

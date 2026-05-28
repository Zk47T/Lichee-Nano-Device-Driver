#!/bin/bash
set -e

make -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- -j$(nproc) suniv-f1c100s-licheepi-nano.dtb
cp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb output/
echo "Done: output/suniv-f1c100s-licheepi-nano.dtb"

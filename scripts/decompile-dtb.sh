#!/bin/bash
# Decompile a device tree blob back to source, to check what actually ended up
# in it (node names, phandles, whether your edit really landed).
#
#   ./scripts/decompile-dtb.sh                 # decompiles output/...dtb
#   ./scripts/decompile-dtb.sh some-other.dtb  # or any dtb you point it at
set -e

cd "$(dirname "$0")/.."

if ! command -v dtc >/dev/null 2>&1; then
	echo "error: dtc not found." >&2
	echo "       sudo apt install device-tree-compiler" >&2
	exit 1
fi

DTB="${1:-output/suniv-f1c100s-licheepi-nano.dtb}"
if [ ! -f "$DTB" ]; then
	echo "error: no such dtb: $DTB" >&2
	echo "       run ./scripts/build-dtb.sh first" >&2
	exit 1
fi

mkdir -p output
OUT="output/$(basename "${DTB%.dtb}").dts"

dtc -I dtb -O dts -o "$OUT" "$DTB" 2>/dev/null

echo "Done: $OUT"
echo
echo "Handy checks:"
echo "  grep -A5 'leds {'  $OUT     # did your LED node land?"
echo "  grep -B2 -A4 usb   $OUT     # dr_mode should be \"peripheral\" for adb"

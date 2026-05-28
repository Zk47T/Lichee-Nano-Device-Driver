#!/bin/bash
set -e

dtc -I dtb -O dts -o output/suniv-f1c100s-licheepi-nano.dts output/suniv-f1c100s-licheepi-nano.dtb
echo "Done: output/suniv-f1c100s-licheepi-nano.dts"

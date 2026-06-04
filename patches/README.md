# Porting Lichee Pi Nano (Allwinner F1C100S) to latest mainline

Target: **Linux 7.0** + **U-Boot 2026.04**. Both built with `arm-linux-gnueabi-` (GCC 11).

The entire port is two small changes — no source patching is required, because the old
fork's binutils ≥2.35 assembly fixes were merged into mainline long ago (~Linux 5.15).

| Component | Upstream | Change |
|-----------|----------|--------|
| U-Boot    | `u-boot/u-boot` tag `v2026.04`   | append `CONFIG_BOOTCOMMAND` to the existing `configs/licheepi_nano_defconfig` |
| Linux     | `torvalds/linux` tag `v7.0`      | add new file `arch/arm/configs/f1c100s_defconfig` |

## Why the U-Boot bootcmd patch is needed

Mainline `licheepi_nano_defconfig` boots to the U-Boot prompt fine, but its default
`bootcmd` (`run distro_bootcmd`) loads `boot.scr` to `scriptaddr=0x81d40000`. On this
32 MB board, current U-Boot reserves more top-of-RAM than the upstream 32 MB layout
assumes, so that address is inside reserved memory and the load is refused
("Reading file would overwrite reserved memory"). The custom `CONFIG_BOOTCOMMAND`
bypasses `scriptaddr`/`boot.scr` entirely, loading kernel + DTB directly to safe low
addresses. No `boot.scr` is needed on the SD card.

## Apply

```bash
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-

# U-Boot
git clone --depth 1 --branch v2026.04 https://github.com/u-boot/u-boot.git
git -C u-boot apply /path/to/uboot-2026.04-licheepi-nano-bootcmd.patch
make -C u-boot licheepi_nano_defconfig
make -C u-boot -j$(nproc) PYTHON=python3
#  -> u-boot/u-boot-sunxi-with-spl.bin

# Linux
git clone --depth 1 --branch v7.0 https://github.com/torvalds/linux.git
git -C linux apply /path/to/linux-7.0-add-f1c100s_defconfig.patch
make -C linux f1c100s_defconfig
make -C linux -j$(nproc) zImage allwinner/suniv-f1c100s-licheepi-nano.dtb
#  -> linux/arch/arm/boot/zImage
#  -> linux/arch/arm/boot/dts/allwinner/suniv-f1c100s-licheepi-nano.dtb
```

Note the DTB now lives under the `allwinner/` subdirectory (it was flat in 5.4).

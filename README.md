# Device Driver Series for Lichee Pi Nano

**Author:** Nguyen Minh Tien  
**Date:** 24/05/2026  
**Website:** https://embeddedlinux.blog/

---

## Hardware

CPU: Allwinner F1C100S — ARM926EJ-S (ARMv5TE) | RAM: 32 MB SiP | Console: UART0 PE0/PE1 115200 8N1  
Kernel: Linux 5.4.77 | Toolchain: `arm-linux-gnueabi` (GCC 11)

---

## 0. Clone This Repo

`linux` and `u-boot-f1c100s` are git submodules. Use `--recurse-submodules` to clone everything in one step:

```bash
git clone --recurse-submodules git@github.com:Zk47T/device-driver-lichee.git
```

If you already cloned without it, fetch the submodules after:

```bash
git submodule update --init
```

---

## 1. Host Requirements

```bash
sudo apt update
sudo apt install -y \
    build-essential git bc flex bison \
    libssl-dev libgnutls28-dev \
    gcc-arm-linux-gnueabi \
    dosfstools u-boot-tools \
    python3
```

Set in every terminal:

```bash
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-
```

---

## 2. Bootloader: U-Boot

The repo is already at `u-boot-f1c100s/` (fork of `github.com/Zk47T/u-boot-f1c100s` with these fixes merged in):
- GCC 10+ `-fcommon` (yylloc multiple-definition error)
- make 4.3 `\#include` escape fix in `scripts/Makefile.lib`
- Python 3.12 PEP 440 version string in `scripts/dtc/pylibfdt/setup.py`
- `binman` → `objcopy`+`cat` for sunxi SPL+U-Boot image assembly

```bash
mkdir -p output
make -C u-boot-f1c100s f1c100s_defconfig
make -C u-boot-f1c100s -j$(nproc) PYTHON=python3
cp u-boot-f1c100s/u-boot-sunxi-with-spl.bin output/
```

Output: `output/u-boot-sunxi-with-spl.bin`

---

## 3. Linux Kernel

The repo is already at `linux/` (fork of `github.com/Zk47T/linux` branch `licheepi-nano-v5.4.y` with these fixes merged in):
- binutils ≥ 2.35 ARM assembly syntax (`#alloc`→`"a"`, `#function`→`%function`, `#object`→`%object`) across 36 `.S` files
- `arch/arm/configs/f1c100s_defconfig` committed directly into the repo

```bash
make -C linux f1c100s_defconfig
make -C linux -j$(nproc) zImage suniv-f1c100s-licheepi-nano.dtb
cp linux/arch/arm/boot/zImage output/
cp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb output/
```

Outputs: `output/zImage`, `output/suniv-f1c100s-licheepi-nano.dtb`

---

## 4. Boot Script

The boot script is already at `files/boot.cmd`. Generate the U-Boot image from it:

```bash
mkimage -C none -A arm -T script -d files/boot.cmd output/boot.scr
```

---

## 5. Root Filesystem

The rootfs is at `files/core-image-minimal-f1c100s.rootfs.tar.xz` (included in the repo).

Built with Yocto Scarthgap. Includes: `libgpiod-tools`, `i2c-tools`, `evtest`, `spidev-test`,
`kmod`, `devmem2`, `strace`, `opkg`, `packagegroup-core-buildessential`.

---

## 6. Flash the SD Card

Plug in the SD card. USB adapters appear as `/dev/sdX`, internal readers as `/dev/mmcblkX`. Set the device once — all commands below use it:

```bash
lsblk -o NAME,SIZE,TYPE,LABEL          # confirm device name

export DEV=/dev/sda                    # change to your device
[[ "$DEV" =~ [0-9]$ ]] && PART="${DEV}p" || PART="${DEV}"
# sdX  → ${PART}1 = /dev/sda1
# mmcblkX → ${PART}1 = /dev/mmcblk0p1

sudo umount ${PART}1 2>/dev/null
sudo umount ${PART}2 2>/dev/null
```

### SD Card Layout

| Region | Content |
|--------|---------|
| 0 – 8 KB | reserved |
| 8 KB | U-Boot SPL + U-Boot (raw, written directly with `dd seek=8`) |
| 1 MB | FAT32 boot partition — `zImage`, `suniv-f1c100s-licheepi-nano.dtb`, `boot.scr` |
| after boot | ext4 rootfs partition |

### Partition

```bash
echo 'label: dos
start=2048, size=128MiB, type=b
start=264192, type=83' | sudo sfdisk $DEV
```

### Write U-Boot

Must be done **after** partitioning but **before** mkfs — SPL+U-Boot live in raw sectors 16–624 (8 KB–312 KB), below the FAT partition which starts at 1 MB. The SPL loads U-Boot proper directly from raw MMC (no FAT file needed).

```bash
sudo dd if=output/u-boot-sunxi-with-spl.bin of=$DEV bs=1k seek=8 conv=notrunc
```

Verify the write worked — serial output should show today's build date, not an old date from a previous image.

### Format

```bash
sudo mkfs.vfat -n boot   ${PART}1
sudo mkfs.ext4 -L rootfs ${PART}2
```

### Copy Boot Files

```bash
sudo mount ${PART}1 /mnt
sudo cp output/zImage                                /mnt/
sudo cp output/suniv-f1c100s-licheepi-nano.dtb       /mnt/
sudo cp output/boot.scr                              /mnt/
sudo umount /mnt
```

### Copy Root Filesystem

```bash
sudo mount ${PART}2 /mnt
sudo tar xfp files/core-image-minimal-f1c100s.rootfs.tar.xz -C /mnt/
sudo umount /mnt && sync
```

---

## 7. Boot

Connect USB-to-TTL: **TX→PE0, RX→PE1, GND→GND** (3.3 V only — never 5 V).

```bash
screen /dev/ttyUSB0 115200
```

Insert SD card, power on. Login: `root` (no password).

---

# Device Driver Series for Lichee Pi Nano

**Author:** Nguyen Minh Tien  
**Date:** 24/05/2026  
**Website:** https://embeddedlinux.blog/

---

## Hardware

CPU: Allwinner F1C100S — ARM926EJ-S (ARMv5TE) | RAM: 32 MB SiP | Console: UART0 PE0/PE1 115200 8N1  
Kernel: Linux 7.0 | U-Boot: v2026.04 | Toolchain: `arm-linux-gnueabi` (GCC 11+)

Verified booting to a `root@f1c100s` login on Linux 7.0.0 (ARMv5TEJ).

---

## Porting model

Both submodules track **pristine upstream**, pinned to release tags:

| Submodule        | Upstream            | Tag        |
|------------------|---------------------|------------|
| `linux`          | `torvalds/linux`    | `v7.0`     |
| `u-boot-f1c100s` | `u-boot/u-boot`     | `v2026.04` |

Because these are upstream repos (nothing to merge into), **all board customizations live
in this repo**, not in the submodules:

- [files/f1c100s_defconfig](files/f1c100s_defconfig) — the kernel config (mainline has none for this board; **required**).
- [files/licheepi_nano_defconfig](files/licheepi_nano_defconfig) — U-Boot config = upstream + a custom `CONFIG_BOOTCOMMAND`.
- [patches/](patches/) — the same two changes as standalone, apply-able patches, for porting onto a fresh upstream checkout.

### Why the U-Boot `bootcmd` override

Mainline `licheepi_nano_defconfig` reaches the U-Boot prompt fine, but its default
`bootcmd` (`run distro_bootcmd`) loads `boot.scr` to `scriptaddr=0x81d40000`. On this
32 MB board, current U-Boot reserves more top-of-RAM than the upstream 32 MB layout
assumes, so that address is now inside reserved memory and the load is refused
(*"Reading file would overwrite reserved memory"*). The custom `CONFIG_BOOTCOMMAND`
bypasses `scriptaddr`/`boot.scr` entirely, loading the kernel + DTB directly to safe
low addresses — so **no `boot.scr` is needed on the SD card.**

---

## 0. Clone This Repo

`linux` and `u-boot-f1c100s` are git submodules pinned to the upstream tags above. Clone
everything in one step:

```bash
git clone --recurse-submodules https://github.com/Zk47T/Lichee-Nano-Device-Driver.git
```

If you already cloned without it:

```bash
git submodule update --init
```

Set cross-compilation variables in every terminal used below:

```bash
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-
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

---

## 2. Bootloader: U-Boot

Copy this repo's U-Boot config (carrying the custom `bootcmd`) into the pristine submodule,
then build:

```bash
mkdir -p output
cp files/licheepi_nano_defconfig u-boot-f1c100s/configs/licheepi_nano_defconfig
make -C u-boot-f1c100s licheepi_nano_defconfig
make -C u-boot-f1c100s -j$(nproc) PYTHON=python3
cp u-boot-f1c100s/u-boot-sunxi-with-spl.bin output/
```

Output: `output/u-boot-sunxi-with-spl.bin`

---

## 3. Linux Kernel

Copy the board defconfig into the pristine submodule, then build. Note the DTB now lives
under the `allwinner/` subdirectory (it was flat in 5.4):

```bash
cp files/f1c100s_defconfig linux/arch/arm/configs/f1c100s_defconfig
make -C linux f1c100s_defconfig
make -C linux -j$(nproc) zImage allwinner/suniv-f1c100s-licheepi-nano.dtb
cp linux/arch/arm/boot/zImage                                       output/
cp linux/arch/arm/boot/dts/allwinner/suniv-f1c100s-licheepi-nano.dtb output/
```

Outputs: `output/zImage`, `output/suniv-f1c100s-licheepi-nano.dtb`

---

## 4. Root Filesystem

The rootfs is at `files/core-image-minimal-f1c100s.rootfs.tar.xz` (included in the repo).

Built with Yocto Scarthgap. Includes: `libgpiod-tools`, `i2c-tools`, `evtest`, `spidev-test`,
`kmod`, `devmem2`, `strace`, `opkg`, `packagegroup-core-buildessential`.

---

## 5. Flash the SD Card

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
| 1 MB | FAT32 boot partition — `zImage`, `suniv-f1c100s-licheepi-nano.dtb` |
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
sync
```

Verify the write worked — serial output should show today's build date, not an old date from a previous image.

### Format

```bash
sudo mkfs.vfat -n boot   ${PART}1
sudo mkfs.ext4 -L rootfs ${PART}2
```

### Copy Boot Files

The baked-in `bootcmd` loads only `zImage` and the DTB from the FAT partition — no `boot.scr` required.

```bash
sudo mount ${PART}1 /mnt
sudo cp output/zImage                          /mnt/
sudo cp output/suniv-f1c100s-licheepi-nano.dtb /mnt/
sudo umount /mnt
```

### Copy Root Filesystem

```bash
sudo mount ${PART}2 /mnt
sudo tar xfp files/core-image-minimal-f1c100s.rootfs.tar.xz -C /mnt/
sudo umount /mnt && sync
```

---

## 6. Boot

Connect USB-to-TTL: **TX→PE0, RX→PE1, GND→GND** (3.3 V only — never 5 V).

```bash
screen /dev/ttyUSB0 115200
```

Insert SD card, power on — it autoboots straight to a login prompt. Login: `root` (no password).

Check the running versions on the board:

```bash
uname -a                                                    # -> Linux 7.0.0 ... armv5tejl
dd if=/dev/mmcblk0 bs=1k skip=8 count=1024 2>/dev/null | strings | grep -m1 "U-Boot 20"
```

---

# ADS1220 IIO driver on Lichee Pi Nano (F1C100S)

A mainline-style Linux IIO driver for the TI ADS1220 24-bit SPI ADC, plus the
board integration to run it on the Lichee Pi Nano. This is **Track B** of the
[roadmap](../../../ads1220/ads1220-linux-device-driver-roadmap.md): the real
kernel driver, not the userspace `spidev` shortcut.

## What was added (all in the `linux/` submodule)

| File | Purpose | For mainline? |
|------|---------|---------------|
| `drivers/iio/adc/ti-ads1220.c` | the driver | **yes** |
| `drivers/iio/adc/Kconfig`, `Makefile` | `CONFIG_TI_ADS1220` | **yes** |
| `Documentation/devicetree/bindings/iio/adc/ti,ads1220.yaml` | DT binding | **yes** |
| `MAINTAINERS` | driver entry | **yes** |
| `arch/arm/boot/dts/allwinner/suniv-f1c100s-licheepi-nano.dts` | board node (ADS1220 on SPI0 CS0) | board-only |
| `files/f1c100s_defconfig` | `CONFIG_IIO` + `CONFIG_TI_ADS1220=m` | board-only |

The two "board-only" changes are kept out of the upstream patch series. The board
DTS change is also exported as `patches/linux-7.0-licheepi-nano-ads1220-dts.patch`.

The upstream-ready series lives in `patches/mainline-ads1220/`:
```
0001-dt-bindings-iio-adc-Add-TI-ADS1220.patch
0002-iio-adc-Add-TI-ADS1220-driver.patch
```
Both pass `checkpatch.pl --strict` with 0 errors / 0 warnings / 0 checks, and the
binding passes `make dt_binding_check` and `make dtbs_check`.

## Wiring

The pin-header SPI on the Lichee Pi Nano is **SPI1 on bank PA** (board silkscreen
`A0..A3` and `SPI1:CS`), not SPI0/PC. The on-board SPI-NOR keeps SPI0 to itself.

| F1C100S | silkscreen | SPI1 fn | ADS1220 |
|---------|-----------|---------|---------|
| PA0 | A0 (SPI1:CS) | CS0  | CS |
| PA1 | A1 (SI) | MOSI | DIN |
| PA2 | A2 (CK) | CLK  | SCLK |
| PA3 | A3 (SO) | MISO | DOUT |
| PE4 | E4 | IRQ (optional) | DRDY |
| 3V3 | 3V3 | — | AVDD + DVDD |
| GND | GND | — | AVSS(AGND) + DGND |

Potentiometer: 3.3V / GND across the track, wiper → **AIN0**. (Internal VREF is
2.048 V, so the pot reads full-scale before the very top of its travel.)

> **DRDY is optional.** With only the 4 SPI wires + power, the driver waits one
> conversion period per sample (single-shot) — perfect for the pot demo. Wire DRDY to
> PE4 and uncomment the `interrupts` lines in the DTS to get interrupt-driven reads and
> DRDY-triggered streaming.

## Build

```bash
cd linux
export ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-

# Config already carries CONFIG_IIO + CONFIG_TI_ADS1220=m via files/f1c100s_defconfig
cp ../files/f1c100s_defconfig arch/arm/configs/f1c100s_defconfig
make f1c100s_defconfig

make -j$(nproc) zImage \
     allwinner/suniv-f1c100s-licheepi-nano.dtb \
     modules
#  -> arch/arm/boot/zImage
#  -> arch/arm/boot/dts/allwinner/suniv-f1c100s-licheepi-nano.dtb
#  -> drivers/iio/adc/ti-ads1220.ko
```

## Deploy to the SD card

FAT (boot) partition — refreshed kernel + DTB:
```bash
sudo cp linux/arch/arm/boot/zImage                                       /mnt/
sudo cp linux/arch/arm/boot/dts/allwinner/suniv-f1c100s-licheepi-nano.dtb /mnt/
```
ext4 (rootfs) partition — the module:
```bash
sudo cp linux/drivers/iio/adc/ti-ads1220.ko /mnt/root/
```

## Test on the board

```bash
screen /dev/ttyUSB0 115200        # the "screen": serial console, login root

insmod ti-ads1220.ko
dmesg | grep ads1220              # probe + DRDY irq

ls /sys/bus/iio/devices/iio:device0/
cat /sys/bus/iio/devices/iio:device0/in_voltage0_raw     # raw 24-bit code
cat /sys/bus/iio/devices/iio:device0/in_voltage0_scale   # mV per code

# live view — turn the pot, watch it track:
watch -n0.2 'cat /sys/bus/iio/devices/iio:device0/in_voltage0_raw'

# millivolts = raw * scale
```

Streaming via the DRDY-triggered buffer (libiio tools in the rootfs):
```bash
iio_info
iio_readdev -b 64 iio:device0 voltage0 | hexdump -C
```

**Done when:** turning the pot changes `in_voltage0_raw` in real time and
`raw * scale` matches a multimeter on the wiper within a few mV.

## Submit upstream

```bash
cd linux
# series is already on branch ads1220-driver and exported to patches/mainline-ads1220/
./scripts/get_maintainer.pl patches/mainline-ads1220/0002-*.patch
git send-email --to linux-iio@vger.kernel.org \
               --cc <maintainers from get_maintainer> \
               ../patches/mainline-ads1220/*.patch
```
Send the binding patch (0001) before the driver (0002). Expect review from the IIO
maintainer (Jonathan Cameron); address feedback and resend as v2.

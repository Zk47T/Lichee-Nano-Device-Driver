
## 0. Quick Board Sanity Tests

Run these first after boot to confirm the image is healthy:

```bash
uname -a                        # kernel version — expect 5.4.77
cat /proc/cpuinfo               # ARM926EJ-S, 408 MHz
free -h                         # expect ~28 MB free (32 MB total SiP)
df -h                           # check rootfs partition is mounted rw
ls /dev/mmc*                    # SD card block device
dmesg | grep -E "error|Error|fail" # scan boot log for problems
```

Peripherals present in the default DTS:

```bash
ls /sys/class/leds/             # licheepi:green:user
ls /sys/bus/i2c/devices/        # i2c-0 if I2C0 enabled
ls /dev/spidev*                 # spidev1.0 if SPI1 enabled
ls /dev/input/                  # event0 if gpio-keys registered
```

Network (if USB-ETH or wifi dongle attached):

```bash
ip addr
```

---

## 1. Device Driver Tasks

### Task 1 — LED

The green user LED is wired to PE6, already registered as a `gpio-leds` device in the DTS.

```bash
echo 1 > /sys/class/leds/licheepi\:green\:user/brightness   # on
echo 0 > /sys/class/leds/licheepi\:green\:user/brightness   # off
echo heartbeat > /sys/class/leds/licheepi\:green\:user/trigger
```

DTS node reference (PE6 = port 4, pin 6):

```dts
leds {
    compatible = "gpio-leds";
    led0 {
        label = "licheepi:green:user";
        gpios = <&pio 4 6 GPIO_ACTIVE_HIGH>;
    };
};
```

---

### Task 2 — GPIO

GPIO line number = **port × 32 + pin offset**. (A=0, B=1, C=2, D=3, E=4)

| Pin  | Line | Note |
|------|------|------|
| PD0  | 96   | I2C0 SDA |
| PD12 | 108  | I2C0 SCK |
| PE3  | 131  | ILI9341 RST |
| PE4  | 132  | Button |
| PE5  | 133  | ILI9341 DC / free |
| PE6  | 134  | LED — use sysfs, not gpioset |
| PE7  | 135  | SPI1 CS |
| PE8  | 136  | SPI1 MOSI |
| PE9  | 137  | SPI1 CLK |
| PE10 | 138  | SPI1 MISO |

**Note:** `gpioinfo`/`gpioget`/`gpioset` (libgpiod v2) require kernel ≥ 5.10 and will fail with `Invalid argument` on kernel 5.4. Use the sysfs interface instead:

```bash
# Export, configure, and drive PE5 (line 133) high
echo 133 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio133/direction
echo 1   > /sys/class/gpio/gpio133/value
echo 0   > /sys/class/gpio/gpio133/value

# Read an input pin (e.g. PE4, line 132)
echo 132 > /sys/class/gpio/export
echo in  > /sys/class/gpio/gpio132/direction
cat        /sys/class/gpio/gpio132/value

# Release when done
echo 133 > /sys/class/gpio/unexport
echo 132 > /sys/class/gpio/unexport
```

---

### Task 3 — Button

Wire: **momentary switch between PE4 and GND**.

DTS node to add inside the root `{ }` of `suniv-f1c100s-licheepi-nano.dts`:

```dts
gpio-keys {
    compatible = "gpio-keys";
    user-button {
        label = "User Button";
        gpios = <&pio 4 4 GPIO_ACTIVE_LOW>;   /* PE4 */
        linux,code = <28>;                     /* KEY_ENTER */
        debounce-interval = <20>;
    };
};
```

```bash
evtest /dev/input/event0              # human-readable key events
cat /dev/input/event0 | hexdump -C   # raw bytes
```

Cross-compile a reader on the host:

```c
// btn.c
#include <stdio.h>
#include <fcntl.h>
#include <linux/input.h>
int main(void) {
    struct input_event ev;
    int fd = open("/dev/input/event0", O_RDONLY);
    while (read(fd, &ev, sizeof ev) == sizeof ev)
        if (ev.type == EV_KEY)
            printf("key %d %s\n", ev.code, ev.value ? "down" : "up");
}
```

```bash
${CROSS_COMPILE}gcc -o btn btn.c
scp btn root@<board-ip>:/tmp/
```

---

### Task 4 — I2C

Connect SSD1306 OLED: **SDA→PD0, SCL→PD12**.

DTS snippet to enable I2C0:

```dts
&i2c0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&i2c0_pd_pins>;
    clock-frequency = <400000>;
};
```

```bash
i2cdetect -y 0               # scan bus — expect device at 0x3c
i2cget  -y 0 0x3c 0x00       # read register 0
i2cset  -y 0 0x3c 0x00 0xAE  # write: display off
```

---

### Task 5 — SPI

Connect ILI9341 LCD: **CLK→PE9, MOSI→PE8, CS→PE7, MISO→PE10**.

DTS snippet to enable SPI1 with a spidev node:

```dts
&spi1 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&spi1_pe_pins>;
    spidev@0 {
        compatible = "rohm,dh2228fv";
        reg = <0>;
        spi-max-frequency = <10000000>;
    };
};
```

Cross-compile on host — short MOSI→MISO for a loopback test:

```c
// spi.c
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
    int fd = open("/dev/spidev1.0", O_RDWR);
    uint8_t mode = SPI_MODE_0, bits = 8;
    uint32_t speed = 1000000;
    ioctl(fd, SPI_IOC_WR_MODE, &mode);
    ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits);
    ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);
    uint8_t tx[] = {0xAA, 0xBB, 0xCC, 0xDD}, rx[4] = {};
    struct spi_ioc_transfer tr = {
        .tx_buf = (unsigned long)tx, .rx_buf = (unsigned long)rx,
        .len = 4, .speed_hz = speed, .bits_per_word = 8,
    };
    ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
    printf("rx: %02x %02x %02x %02x\n", rx[0], rx[1], rx[2], rx[3]);
}
```

```bash
${CROSS_COMPILE}gcc -o spi spi.c
scp spi root@<board-ip>:/tmp/
```

---

### Task 6 — Kernel Module

```c
// hello.c
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
static int hello_open(struct inode *i, struct file *f) {
    pr_info("hello: opened\n");
    return 0;
}
static const struct file_operations fops = { .owner = THIS_MODULE, .open = hello_open };
static struct miscdevice dev = { MISC_DYNAMIC_MINOR, "hello", &fops };
static int __init m_init(void) { return misc_register(&dev); }
static void __exit m_exit(void) { misc_deregister(&dev); }
module_init(m_init); module_exit(m_exit);
MODULE_LICENSE("GPL");
```

```makefile
# Makefile
KDIR := ../linux
obj-m := hello.o
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

```bash
make

scp hello.ko root@<board-ip>:/tmp/
# on the board:
insmod /tmp/hello.ko
dmesg | tail -3
rmmod hello
```

---

## 2. Modify the Device Tree

Edit the board DTS directly in the kernel tree:

```bash
$EDITOR linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dts
```

Rebuild DTB only (seconds, not minutes):

```bash
make -C linux suniv-f1c100s-licheepi-nano.dtb
```

Deploy to the board:

```bash
# option A — over network
scp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb \
    root@<board-ip>:/boot/suniv-f1c100s-licheepi-nano.dtb
ssh root@<board-ip> reboot

# option B — SD card
sudo mount /dev/sdX1 /mnt
sudo cp linux/arch/arm/boot/dts/suniv-f1c100s-licheepi-nano.dtb /mnt/
sudo umount /mnt
```

---

## 3. Yocto Build (alternative path)

If you have the full Yocto Scarthgap environment (`meta-f1c100s` layer):

```bash
cd poky
source oe-init-build-env build-f1c100s
bitbake core-image-minimal
```

The output image symlink is at `tmp-glibc/deploy/images/f1c100s/sdimg`. Flash it:

```bash
sudo bmaptool copy tmp-glibc/deploy/images/f1c100s/sdimg /dev/sdX
```

To switch to device-driver mode (uses `device-driver.defconfig` + meta-layer DTS), add to
`build-f1c100s/conf/local.conf`:

```
DEVICE_DRIVER = "1"
```

Then rebuild: `bitbake core-image-minimal`.

---

## Pin Reference

| Pin  | GPIO Line | Used by        |
|------|-----------|----------------|
| PA3  | 3         | LED (external) |
| PD0  | 96        | I2C0 SDA       |
| PD12 | 108       | I2C0 SCK       |
| PE3  | 131       | ILI9341 RST    |
| PE4  | 132       | Button         |
| PE5  | 133       | ILI9341 DC     |
| PE6  | 134       | LED (on-board) |
| PE7  | 135       | SPI1 CS        |
| PE8  | 136       | SPI1 MOSI      |
| PE9  | 137       | SPI1 CLK       |
| PE10 | 138       | SPI1 MISO      |

# BSP-Lab 01 — Boot Issues: Individual Reproduce Commands
# 10 issues | Real commands | Exact expected output

---

## Common Setup (do once before all issues)

```bash
# Source Yocto environment
cd ~/yocto/poky && source oe-init-build-env build

# Standard working QEMU boot command — reference for all issues
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a57 \
  -m 1024 \
  -nographic \
  -kernel /home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/Image \
  -dtb /home/kotesh/dtstest/kotesh-test.dtb \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive if=none,format=raw,file=/home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4,id=hd0 \
  -device virtio-blk-device,drive=hd0
```

---

## Issue 01 — Compatible String Mismatch

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# Change the kotesh-dummy node compatible to wrong value:
#   compatible = "kotesh,my-dummy";   ← was "kotesh,mydummy" (hyphen added)
```

### Step 2: Rebuild DTB only (no bitbake needed)
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command above)

### Step 4: Verify broken state
```bash
# After login as root:
dmesg | grep MY_DUMMY
# (no output — probe never called)

cat /proc/device-tree/kotesh-dummy/compatible
# kotesh,my-dummy   ← wrong string visible here

ls /sys/bus/platform/devices/ | grep kotesh-dummy
# (no output — device not registered)

lsmod | grep my_dummy
# my_dummy_driver 16384 0 - Live ...  ← module loaded but probe skipped
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Change back: compatible = "kotesh,mydummy";
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
# Reboot QEMU
```

### Expected fixed output
```
dmesg | grep MY_DUMMY
# [    7.100753] MY_DUMMY: probe successful
```

---

## Issue 02 — Device Node Disabled

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# In kotesh-dummy node, change:
#   status = "okay";  →  status = "disabled";
```

### Step 2: Rebuild DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command above)

### Step 4: Verify broken state
```bash
cat /proc/device-tree/kotesh-dummy/status
# disabled

dmesg | grep MY_DUMMY
# [x.x] my_dummy_driver: loading out-of-tree module taints kernel.
# (no "probe successful" line!)

ls /sys/bus/platform/devices/ | grep kotesh-dummy
# (no output — device not registered at all)
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Change back: status = "okay";
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
# Reboot QEMU
```

### Expected fixed output
```
cat /proc/device-tree/kotesh-dummy/status
# okay
dmesg | grep MY_DUMMY
# [    4.877957] MY_DUMMY: probe successful
ls /sys/bus/platform/devices/ | grep kotesh-dummy
# kotesh-dummy
```

---

## Issue 03 — Missing reg Property

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# In kotesh-reg@20000000 node, comment out reg:
#   /* reg = <0x0 0x20000000 0x0 0x1000>; */
# Also rename node (remove address): kotesh-reg {
```

### Step 2: Rebuild DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command above)

### Step 4: Verify broken state
```bash
dmesg | grep KOTESH_REG
# [    6.960222] kotesh_reg_driver: loading out-of-tree module taints kernel.
# [    7.020712] KOTESH_REG: failed to get memory resource
# [    7.021339] kotesh_reg: probe of kotesh-reg failed with error -22

ls /proc/device-tree/kotesh-reg/
# compatible  name  status
# (no "reg" file!)
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Restore:
# kotesh-reg@20000000 {
#     compatible = "kotesh,reg-driver";
#     reg = <0x0 0x20000000 0x0 0x1000>;
#     status = "okay";
# };
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Expected fixed output
```
dmesg | grep KOTESH_REG
# [    6.866715] KOTESH_REG: probe successful
# [    6.867170] KOTESH_REG: memory region start=0x20000000 size=0x1000

ls /proc/device-tree/kotesh-reg@20000000/
# compatible  name  reg  status
```

---

## Issue 04 — Wrong Interrupt Number (IRQ Conflict)

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# In kotesh-irq@20001000, change interrupts to SPI 3 (used by arch_timer):
#   interrupts = <0x0 0x03 0x4>;   ← was 0x0a (SPI 10)
```

### Step 2: Rebuild DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command above)

### Step 4: Verify broken state
```bash
dmesg | grep -i "KOTESH_IRQ"
# [    7.079728] KOTESH_IRQ: module init
# [    7.096566] KOTESH_IRQ: platform_driver_register returned 0
# (no probe called!)

cat /proc/interrupts
# 11:  35842  GIC-0  27 Level  arch_timer   ← SPI 3 already taken!

echo "kotesh-irq" > /sys/bus/platform/drivers/kotesh_irq/bind
# sh: write error: Resource temporarily unavailable
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Restore: interrupts = <0x0 0x0a 0x4>;   (SPI 10 = free)
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### GIC interrupt format reference
```
interrupts = <type  spi_number  trigger>;
# type:    0=SPI, 1=PPI
# trigger: 1=edge-rising, 4=level-high
# Linux IRQ = spi_number + 32
```

---

## Issue 05 — Probe Deferral

### Step 1: Observe it (DTS already set up with interrupt-parent)
```bash
# The kotesh-irq node has:
#   interrupt-parent = <0x8001>;
#   interrupts = <0x0 0x0a 0x4>;
# This causes dependency on GIC → cpu@0 → probe deferral
```

### Step 2: Rebuild DTB and Boot QEMU (standard command)

### Step 3: Verify deferred state
```bash
cat /sys/kernel/debug/devices_deferred
# 20001000.kotesh-irq    platform: wait for supplier cpu@0

ls /sys/bus/platform/devices/20001000.kotesh-irq/
# waiting_for_supplier file present

dmesg | grep KOTESH_IRQ
# KOTESH_IRQ: module init
# (no probe message!)

ls /sys/bus/platform/drivers/kotesh_irq/
# bind  module  uevent  unbind
# (no device symlink = not bound)
```

### Step 4: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Remove interrupts properties from kotesh-irq node:
# Remove: interrupt-parent = <0x8001>;
# Remove: interrupts = <0x0 0x0a 0x4>;
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

---

## Issue 06 — Missing Clock Property

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# In kotesh-clk@20002000 node, comment out:
#   /* clocks = <0x8000>; */
#   /* clock-names = "apb_pclk"; */
```

### Step 2: Rebuild DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command)

### Step 4: Verify broken state
```bash
dmesg | grep KOTESH_CLK
# [    7.232972] KOTESH_CLK: probe called
# [    7.234111] KOTESH_CLK: failed to get clock, error=-2
# [    7.234770] kotesh_clk: probe of 20002000.kotesh-clk failed with error -2

ls /proc/device-tree/kotesh-clk@20002000/
# compatible  name  reg  status
# (no "clocks" or "clock-names"!)
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Restore:
#   clocks = <0x8000>;
#   clock-names = "apb_pclk";
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Expected fixed output
```
dmesg | grep KOTESH_CLK
# [    6.922211] KOTESH_CLK: probe called
# [    6.922761] KOTESH_CLK: got clock successfully
# [    6.923185] KOTESH_CLK: probe successful
```

---

## Issue 07 — Missing Regulator Property

### Step 1: Break it
```bash
nano ~/dtstest/qemu-virt.dts
# In kotesh-vcc@20003000, comment out:
#   /* vcc-supply = <0x8000>; */
```

### Step 2: Rebuild DTB
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Step 3: Boot QEMU (standard command)

### Step 4: Verify broken state
```bash
dmesg | grep KOTESH_VCC
# [    6.930085] KOTESH_VCC: probe called
# [    6.930654] KOTESH_VCC: failed to get regulator, error=-19

ls /proc/device-tree/kotesh-vcc@20003000/
# compatible  name  reg  status
# (no "vcc-supply"!)
```

### Step 5: Fix it
```bash
nano ~/dtstest/qemu-virt.dts
# Restore: vcc-supply = <0x8000>;
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

### Expected fixed output
```
dmesg | grep KOTESH_VCC
# [    6.774723] KOTESH_VCC: probe called
# [    6.775256] KOTESH_VCC: got regulator successfully
# [    6.775771] KOTESH_VCC: probe successful
```

---

## Issue 08 — Missing of_match_table (No DT Matching)

### Step 1: Break it
```bash
nano ~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/files/kotesh_of_driver.c
# Remove/comment out of_match_table from platform_driver struct:
#   .of_match_table = of_match_ptr(kotesh_of_ids),   ← delete this line
```

### Step 2: Rebuild
```bash
cd ~/yocto/poky && source oe-init-build-env build
MACHINE=qemuarm64 bitbake kotesh-of-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
```

### Step 3: Boot QEMU (standard command)

### Step 4: Verify broken state
```bash
dmesg | grep KOTESH_OF
# (no output at all — completely silent!)

lsmod | grep kotesh_of
# kotesh_of_driver 16384 0 - Live ...   ← module loaded

ls /sys/bus/platform/drivers/ | grep kotesh_of
# kotesh_of   ← driver registered

ls /sys/bus/platform/devices/ | grep kotesh-of
# 20004000.kotesh-of   ← device exists

cat /sys/bus/platform/devices/20004000.kotesh-of/uevent
# OF_COMPATIBLE_0=kotesh,of-driver
# MODALIAS=of:Nkotesh-ofT(null)Ckotesh,of-driver
# (no DRIVER= line = unbound!)
```

### Step 5: Fix it
```bash
nano ~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/files/kotesh_of_driver.c
# Restore: .of_match_table = of_match_ptr(kotesh_of_ids),
MACHINE=qemuarm64 bitbake kotesh-of-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
```

---

## Issue 09 — Driver Not Included in Image

### Step 1: Break it
```bash
nano ~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend
# Comment out: # IMAGE_INSTALL += "kotesh-of-driver"
```

### Step 2: Rebuild image
```bash
cd ~/yocto/poky && source oe-init-build-env build
MACHINE=qemuarm64 bitbake core-image-minimal
```

### Step 3: Boot QEMU (standard command)

### Step 4: Verify broken state
```bash
find /lib/modules -name "kotesh_of*"
# (no output — .ko not in rootfs!)

ls /sys/bus/platform/drivers/ | grep kotesh_of
# (no output — driver never loaded!)

dmesg | grep KOTESH_OF
# (no output)

ls /proc/device-tree/kotesh-of@20004000/
# compatible  name  reg  status   ← node exists but driver missing
```

### Step 5: Fix it
```bash
nano ~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend
# Uncomment: IMAGE_INSTALL += "kotesh-of-driver"
MACHINE=qemuarm64 bitbake core-image-minimal
```

### Expected fixed output
```
find /lib/modules -name "kotesh_of*"
# /lib/modules/5.15.194-yocto-standard/extra/kotesh_of_driver.ko

dmesg | grep KOTESH_OF
# KOTESH_OF: probe called
# KOTESH_OF: probe successful
```

---

## Issue 10 — Multiple Drivers Same Compatible (Conflict)

### Step 1: Observe it (already set up — both multi drivers in image)
```bash
# kotesh_multi_a.c → compatible = "kotesh,multi-driver"
# kotesh_multi_b.c → compatible = "kotesh,multi-driver"  (same!)
# DTS: kotesh-multi@20005000 { compatible = "kotesh,multi-driver"; }
```

### Step 2: Build and Boot QEMU (standard command)

### Step 3: Verify conflict
```bash
dmesg | grep KOTESH_MULTI
# [    7.063561] KOTESH_MULTI_A: probe called!
# [    7.063997] KOTESH_MULTI_A: I am driver A — probe successful
# (KOTESH_MULTI_B never appears!)

lsmod | grep kotesh_multi
# kotesh_multi_b 16384 0 - Live ...   ← B loaded
# kotesh_multi_a 16384 0 - Live ...   ← A loaded

cat /sys/bus/platform/devices/20005000.kotesh-multi/uevent | grep DRIVER
# DRIVER=kotesh_multi_a   ← A won, B silently ignored

ls /sys/bus/platform/drivers/kotesh_multi_b/
# bind  module  uevent  unbind
# (no device symlink = B never bound)
```

### Step 4: Fix it
```bash
# Option 1: Remove driver B from image
nano ~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend
# Comment out: # IMAGE_INSTALL += "kotesh-multi-driver-b"

# Option 2: Give unique compatible strings
# Driver A: compatible = "kotesh,multi-driver-v1"
# Driver B: compatible = "kotesh,multi-driver-v2"
# DTS: compatible = "kotesh,multi-driver-v1";
```

---

## Quick Diagnostic Cheat Sheet — All 10 Issues

| # | Issue | First Command to Run | Key Symptom |
|---|---|---|---|
| 01 | Compatible mismatch | `cat /proc/device-tree/<node>/compatible` | Wrong string |
| 02 | Node disabled | `cat /proc/device-tree/<node>/status` | Shows "disabled" |
| 03 | Missing reg | `ls /proc/device-tree/<node>/` | No "reg" file |
| 04 | Wrong IRQ | `cat /proc/interrupts` | SPI already taken |
| 05 | Probe deferral | `cat /sys/kernel/debug/devices_deferred` | Device listed there |
| 06 | Missing clock | `dmesg \| grep CLK` + `ls /proc/device-tree/<node>/` | error=-2, no clocks |
| 07 | Missing regulator | `dmesg \| grep VCC` + `ls /proc/device-tree/<node>/` | error=-19, no vcc-supply |
| 08 | No of_match_table | `ls /sys/bus/platform/drivers/<drv>/` | No device symlink |
| 09 | Driver not in image | `find /lib/modules -name "*.ko"` | .ko file missing |
| 10 | Duplicate compatible | `cat /sys/bus/platform/devices/<dev>/uevent` | Only first driver bound |

## DTB Rebuild Command (use after every DTS change)
```bash
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts
```

## QEMU virt Phandle Reference
```
apb-pclk clock  : phandle = 0x8000   (use for clocks/vcc-supply)
GIC controller  : phandle = 0x8001   (use for interrupt-parent)
Free MMIO base  : 0x20000000         (use for reg addresses)
```

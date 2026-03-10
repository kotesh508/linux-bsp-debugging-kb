# Issue 04 — Wrong Interrupt Number (IRQ Conflict)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver probe fails with `Resource temporarily unavailable` or probe is never called. Manual bind also fails:

```bash
root@qemuarm64:~# echo "kotesh-irq" > /sys/bus/platform/drivers/kotesh_irq/bind
sh: write error: Resource temporarily unavailable

root@qemuarm64:~# dmesg | grep -i "KOTESH_IRQ"
[    7.079728] KOTESH_IRQ: module init
[    7.096566] KOTESH_IRQ: platform_driver_register returned 0
# No probe called!
```

---

## 🔍 Stage Identification

**Stage:** Driver probe stage  
The driver registers successfully but probe is blocked because the IRQ number specified in the DTS conflicts with an already-registered interrupt on the system.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg for IRQ errors
dmesg | grep -i "irq\|interrupt"

# 2. Check all registered interrupts
cat /proc/interrupts

# 3. Check iomem for resource conflicts
cat /proc/iomem

# 4. Try manual bind and observe error
echo "kotesh-irq" > /sys/bus/platform/drivers/kotesh_irq/bind
# sh: write error: Resource temporarily unavailable

# 5. Check deferred probe list
cat /sys/kernel/debug/devices_deferred
```

---

## 🔍 Root Cause

The DTS node used **SPI 3** (`interrupts = <0x0 0x3 0x4>`):

```dts
/* BROKEN — SPI 3 already used by arch_timer */
kotesh-irq {
    compatible = "kotesh,irq-driver";
    interrupt-parent = <0x8001>;
    interrupts = <0x0 0x3 0x4>;   /* SPI 3 = Linux IRQ 35 — CONFLICT! */
    status = "okay";
};
```

Checking `/proc/interrupts` revealed:
```
 11:   35842   GIC-0  27 Level   arch_timer   ← SPI 3 (27-16=11... GIC offset)
 46:       2   GIC-0  34 Level   rtc-pl031
 47:      14   GIC-0  33 Level   uart-pl011
```

GIC SPI interrupts map as: **Linux IRQ = SPI number + 32**  
So `SPI 3 = Linux IRQ 35` which was already claimed by `arch_timer`.

When two devices claim the same IRQ without `IRQF_SHARED`, the kernel returns
`-EBUSY` which surfaces as `Resource temporarily unavailable`.

---

## ✅ Fix

Use a free SPI number. Check `/proc/interrupts` to find unused lines:

```bash
# On a running system, identify free IRQs
cat /proc/interrupts
# Used: GIC-0 27(arch_timer), 79(virtio0), 34(rtc), 33(uart), 23(pmu)
# Free: SPI 5, 10, 15, 20... anything not listed
```

Fix the DTS to use **SPI 10** (free):

```dts
/* FIXED — SPI 10, not used by any other device */
kotesh-irq@20001000 {
    compatible = "kotesh,irq-driver";
    reg = <0x0 0x20001000 0x0 0x1000>;
    interrupt-parent = <0x8001>;
    interrupts = <0x0 0x0a 0x4>;   /* SPI 10 = Linux IRQ 42 — FREE */
    status = "okay";
};
```

Recompile DTB:
```bash
dtc -I dts -O dtb -o /home/kotesh/dtstest/kotesh-test.dtb \
    /home/kotesh/dtstest/qemu-virt.dts
```

---

## 🧠 Interview Explanation

> Each interrupt line on a GIC can only be owned by one device unless `IRQF_SHARED` is used. In the Device Tree, the `interrupts` property specifies the interrupt type, number, and trigger mode. For ARM GIC, SPI interrupts map to Linux IRQ numbers as `SPI + 32`. If the DTS assigns an SPI number that is already claimed by another device (like `arch_timer` on SPI 3), `devm_request_irq()` returns `-EBUSY`, probe fails with `Resource temporarily unavailable`. The fix is to check `/proc/interrupts` on a running system to identify free interrupt lines and assign one to the new device.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-irq-driver/files/kotesh_irq_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-irq-driver/kotesh-irq-driver.bb` |
| Image append | `~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend` |

---

## 🖥️ QEMU Boot Command

```bash
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

## 🧪 How to Reproduce

```bash
# Step 1: Set IRQ to conflicting SPI 3 in DTS
nano ~/dtstest/qemu-virt.dts
# Set: interrupts = <0x0 0x3 0x4>;

# Step 2: Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# Step 3: Boot QEMU (command above)

# Step 4: Observe broken state
cat /proc/interrupts           # SPI 3 already taken by arch_timer
echo "kotesh-irq" > /sys/bus/platform/drivers/kotesh_irq/bind
# sh: write error: Resource temporarily unavailable

# Step 5: Fix — use free SPI
# interrupts = <0x0 0x0a 0x4>;   SPI 10
# Recompile, reboot
```

---

## ✅ GIC Interrupt Cell Format (ARM)

```dts
interrupts = <type  spi_number  trigger>;
/*
  type:
    0 = SPI (Shared Peripheral Interrupt)
    1 = PPI (Private Peripheral Interrupt)

  spi_number:
    Actual SPI number (Linux IRQ = spi_number + 32)

  trigger:
    1 = IRQ_TYPE_EDGE_RISING
    2 = IRQ_TYPE_EDGE_FALLING
    4 = IRQ_TYPE_LEVEL_HIGH
    8 = IRQ_TYPE_LEVEL_LOW
*/
```

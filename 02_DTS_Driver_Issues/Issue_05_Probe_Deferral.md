# Issue 05 — Probe Deferral (Waiting for Supplier)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver module loads, device is registered, but probe is **silently never called**. Manual bind fails with `Resource temporarily unavailable`. The device appears in the deferred probe list:

```bash
root@qemuarm64:~# cat /sys/kernel/debug/devices_deferred
20001000.kotesh-irq    platform: wait for supplier cpu@0

root@qemuarm64:~# cat /sys/bus/platform/devices/20001000.kotesh-irq/waiting_for_supplier
# file exists — device is waiting

root@qemuarm64:~# dmesg | grep -i "KOTESH_IRQ"
[    4.963009] KOTESH_IRQ: module init
# No probe called!
```

---

## 🔍 Stage Identification

**Stage:** Driver probe deferral stage  
The kernel attempted to probe the device but discovered that a required supplier (dependency) was not yet ready. Instead of failing permanently, the kernel **defers the probe** and retries later. If the supplier never becomes ready, probe is never called.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg — module loads but no probe
dmesg | grep -i "KOTESH_IRQ"
# KOTESH_IRQ: module init
# (no probe message)

# 2. Check deferred probe list — KEY CHECK
cat /sys/kernel/debug/devices_deferred
# 20001000.kotesh-irq    platform: wait for supplier cpu@0

# 3. Check waiting_for_supplier file
ls /sys/bus/platform/devices/20001000.kotesh-irq/
# waiting_for_supplier file present = probe deferred

# 4. Confirm device and driver both exist but unbound
ls /sys/bus/platform/drivers/kotesh_irq/
# bind  module  uevent  unbind  (no device symlink!)

cat /sys/bus/platform/devices/20001000.kotesh-irq/driver 2>/dev/null \
    || echo "no driver bound"
# no driver bound
```

---

## 🔍 Root Cause

The device node had `interrupt-parent = <0x8001>` pointing to the GIC, which in turn has a dependency on `cpu@0` through the interrupt affinity framework. The kernel's **supplier/consumer** model detected this dependency and deferred probe until `cpu@0` supplier was resolved.

```dts
/* This node causes probe deferral */
kotesh-irq@20001000 {
    compatible = "kotesh,irq-driver";
    reg = <0x0 0x20001000 0x0 0x1000>;
    interrupt-parent = <0x8001>;      /* GIC — linked to cpu@0 */
    interrupts = <0x0 0x0a 0x4>;
    status = "okay";
};
```

**How probe deferral works:**
1. Kernel calls `probe()` on device
2. Driver calls `platform_get_irq()` or similar
3. Kernel detects a supplier dependency is not ready
4. Kernel returns `-EPROBE_DEFER` internally
5. Device is added to deferred probe list
6. Kernel retries probe periodically
7. If supplier never resolves → probe never succeeds

```
/sys/kernel/debug/devices_deferred shows:
20001000.kotesh-irq    platform: wait for supplier cpu@0
                                              ^^^^^^^^^^^
                                              This is the unresolved dependency
```

---

## ✅ Fix

### Option 1: Remove interrupt dependency (simplest for virtual/dummy devices)

If the device doesn't actually need interrupts (e.g. a dummy/test driver), remove the `interrupts` property from the DTS:

```dts
/* FIXED — no interrupt dependency, no deferral */
kotesh-irq@20001000 {
    compatible = "kotesh,irq-driver";
    reg = <0x0 0x20001000 0x0 0x1000>;
    status = "okay";
    /* interrupts removed — no supplier dependency */
};
```

### Option 2: Handle `-EPROBE_DEFER` explicitly in driver

For real drivers that need the IRQ, return `-EPROBE_DEFER` gracefully:

```c
static int kotesh_irq_probe(struct platform_device *pdev)
{
    int irq;

    irq = platform_get_irq(pdev, 0);
    if (irq == -EPROBE_DEFER) {
        dev_info(&pdev->dev, "IRQ not ready, deferring probe\n");
        return -EPROBE_DEFER;   /* kernel will retry later */
    }
    if (irq < 0) {
        dev_err(&pdev->dev, "failed to get IRQ: %d\n", irq);
        return irq;
    }
    /* ... rest of probe */
}
```

### Option 3: Use `devm_platform_get_irq_optional()` for optional IRQs

```c
irq = platform_get_irq_optional(pdev, 0);
if (irq < 0 && irq != -ENXIO)
    return irq;
```

---

## 🧠 Interview Explanation

> Probe deferral is a Linux kernel mechanism where a driver's `probe()` function returns `-EPROBE_DEFER` to indicate that a required resource or dependency is not yet available. The kernel adds the device to a deferred probe list and retries probe after other devices finish initializing. Common causes include: a clock provider not yet registered, a regulator not yet available, a GPIO controller not yet probed, or an interrupt controller dependency not resolved. You can identify probe deferral by checking `/sys/kernel/debug/devices_deferred` — it shows each deferred device and the reason. The fix is either to ensure the supplier initializes first (using `initcall` ordering or `depends-on` in DTS), or to handle `-EPROBE_DEFER` explicitly in the driver.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-irq-driver/files/kotesh_irq_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-irq-driver/kotesh-irq-driver.bb` |

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
# Step 1: Add interrupt-parent pointing to GIC in DTS node
nano ~/dtstest/qemu-virt.dts
# Add:
# interrupt-parent = <0x8001>;
# interrupts = <0x0 0x0a 0x4>;

# Step 2: Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# Step 3: Boot QEMU (command above)

# Step 4: Observe deferred probe
cat /sys/kernel/debug/devices_deferred
# 20001000.kotesh-irq    platform: wait for supplier cpu@0

ls /sys/bus/platform/devices/20001000.kotesh-irq/ | grep waiting
# waiting_for_supplier

# Step 5: Fix — remove interrupts property from DTS
# Recompile, reboot — probe succeeds
```

---

## ✅ Key Diagnostic Commands

```bash
# Most important — check deferred probe list
cat /sys/kernel/debug/devices_deferred

# Check if device is waiting for supplier
ls /sys/bus/platform/devices/<device>/waiting_for_supplier

# Check driver binding
ls /sys/bus/platform/drivers/<driver>/   # device symlink missing = not bound

# Check for EPROBE_DEFER in dmesg
dmesg | grep -i "defer\|EPROBE"
```



short answer with issue root cause
------------------------------------
What i Did Step by Step
What i Modified
i added interrupt-parent and interrupts to the kotesh-irq DTS node:
dtskotesh-irq@20001000 {
    compatible = "kotesh,irq-driver";
    reg = <0x0 0x20001000 0x0 0x1000>;
    interrupt-parent = <0x8001>;    /* <-- this caused deferral */
    interrupts = <0x0 0x0a 0x4>;   /* <-- this caused deferral */
    status = "okay";
};

What i Checked
bash# 1. Module loaded but probe never called
dmesg | grep -i "KOTESH_IRQ"
# Only: KOTESH_IRQ: module init

# 2. Manual bind failed
echo "20001000.kotesh-irq" > /sys/bus/platform/drivers/kotesh_irq/bind
# Resource temporarily unavailable

# 3. KEY CHECK — found the real reason
cat /sys/kernel/debug/devices_deferred
# 20001000.kotesh-irq    platform: wait for supplier cpu@0

# 4. Confirmed waiting_for_supplier file exists
ls /sys/bus/platform/devices/20001000.kotesh-irq/
# waiting_for_supplier  ← this file means probe is deferred
```

---

### Why It Happened
```
interrupt-parent = <0x8001>  →  points to GIC
GIC  →  has dependency on cpu@0
cpu@0  →  never resolves as a supplier in our QEMU setup
Result  →  probe deferred forever

The Fix
Remove the interrupt properties from the DTS node — since our driver is a dummy driver and doesn't actually need interrupts:
dts/* FIXED */
kotesh-irq@20001000 {
    compatible = "kotesh,irq-driver";
    reg = <0x0 0x20001000 0x0 0x1000>;
    status = "okay";
    /* interrupts removed → no supplier dependency → probe called */
};

One Line Summary for Interview

Probe deferral happens when a device depends on a supplier (like GIC→cpu@0) that isn't ready yet. The kernel silently defers probe. Diagnosed via /sys/kernel/debug/devices_deferred. Fixed by removing the unresolvable dependency.


---

## 📌 Comparison — Issue 03 vs 04 vs 05

| | Issue 03 | Issue 04 | Issue 05 |
|---|---|---|---|
| Root cause | Missing `reg` | Wrong IRQ number | Supplier dependency |
| Probe called | ✅ Fails midway | ❌ Blocked | ❌ Deferred |
| Error message | `probe failed -22` | `Resource unavailable` | Silent — no message |
| Key diagnostic | `ls /proc/device-tree/` | `cat /proc/interrupts` | `cat /sys/kernel/debug/devices_deferred` |
| Fix | Add `reg` property | Use free SPI number | Remove dependency or handle `-EPROBE_DEFER` |

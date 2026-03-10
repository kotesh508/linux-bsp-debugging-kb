# Issue 08 — Missing CONFIG_OF / of_match_table (No DT Matching)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Module loads, driver registers, device exists — but **probe is never called**. No error messages at all:

```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_OF"
# (no output at all!)

root@qemuarm64:~# lsmod | grep kotesh_of
kotesh_of_driver 16384 0 - Live 0xffffffc000bbf000 (O)

root@qemuarm64:~# ls /sys/bus/platform/drivers/ | grep kotesh_of
kotesh_of

root@qemuarm64:~# ls /sys/bus/platform/devices/ | grep kotesh-of
20004000.kotesh-of

root@qemuarm64:~# cat /sys/bus/platform/devices/20004000.kotesh-of/uevent
OF_NAME=kotesh-of
OF_FULLNAME=/kotesh-of@20004000
OF_COMPATIBLE_0=kotesh,of-driver
OF_COMPATIBLE_N=1
MODALIAS=of:Nkotesh-ofT(null)Ckotesh,of-driver
# Driver and device never matched!
```

---

## 🔍 Stage Identification

**Stage:** Driver-device matching stage  
The kernel cannot match the device to the driver because the driver has no `of_match_table`. Without this table, the platform bus has no way to know which DT compatible strings this driver handles.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg — no probe message at all
dmesg | grep -i "KOTESH_OF"
# (empty — not even a loading message)

# 2. Module is loaded
lsmod | grep kotesh_of
# kotesh_of_driver 16384 0 - Live ...

# 3. Driver registered on platform bus
ls /sys/bus/platform/drivers/ | grep kotesh_of
# kotesh_of

# 4. Device exists on platform bus
ls /sys/bus/platform/devices/ | grep kotesh-of
# 20004000.kotesh-of

# 5. Check uevent — device has compatible but no driver symlink
cat /sys/bus/platform/devices/20004000.kotesh-of/uevent
# OF_COMPATIBLE_0=kotesh,of-driver
# MODALIAS=of:Nkotesh-ofT(null)Ckotesh,of-driver

# 6. No driver symlink in device directory
ls /sys/bus/platform/devices/20004000.kotesh-of/
# no "driver" symlink = unbound
```

---

## 🔍 Root Cause

The driver was missing the `of_match_table` in its `platform_driver` struct:

```c
/* BROKEN — no of_match_table */
static struct platform_driver kotesh_of_driver = {
    .probe  = kotesh_of_probe,
    .remove = kotesh_of_remove,
    .driver = {
        .name = "kotesh_of",
        /* of_match_table missing! */
    },
};
```

This simulates what happens when `CONFIG_OF` is not enabled or when a driver
is written without Device Tree support.

**How driver-device matching works in Linux:**

```
DTS node compatible = "kotesh,of-driver"
         ↓
Kernel reads DTB → creates platform_device
         ↓
Kernel looks for driver with matching of_match_table entry
         ↓
No of_match_table in driver → NO MATCH → probe never called
```

Without `of_match_table`, the platform bus only matches by **driver name** —
and the device name `20004000.kotesh-of` does not match driver name `kotesh_of`.

---

## ✅ Fix

Add `of_match_table` to the driver with the correct compatible string:

```c
/* FIXED — with of_match_table */
#include <linux/of.h>

static const struct of_device_id kotesh_of_ids[] = {
    { .compatible = "kotesh,of-driver" },   /* must match DTS */
    { }
};
MODULE_DEVICE_TABLE(of, kotesh_of_ids);

static struct platform_driver kotesh_of_driver = {
    .probe  = kotesh_of_probe,
    .remove = kotesh_of_remove,
    .driver = {
        .name           = "kotesh_of",
        .of_match_table = of_match_ptr(kotesh_of_ids),  /* added! */
    },
};
```

**DTS node (unchanged — correct):**
```dts
kotesh-of@20004000 {
    compatible = "kotesh,of-driver";
    reg = <0x0 0x20004000 0x0 0x1000>;
    status = "okay";
};
```

**Verification after fix:**
```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_OF"
[    7.123456] KOTESH_OF: probe called
[    7.124000] KOTESH_OF: probe successful
```

---

## 🧠 Interview Explanation

> `CONFIG_OF` enables Device Tree support in the Linux kernel. When enabled, drivers use `of_match_table` inside `platform_driver.driver` to declare which DT `compatible` strings they handle. The kernel matches this table against the `compatible` property of DT nodes to call the driver's `probe()`. If `of_match_table` is missing — either because `CONFIG_OF` is disabled or the developer forgot to add it — the kernel cannot perform DT-based matching. The driver registers successfully and the device is created, but they are never bound and probe is never called. There are no error messages, making this a silent failure that is easy to miss. The fix is to add `of_match_table` with the correct compatible string and include `<linux/of.h>`.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/files/kotesh_of_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/kotesh-of-driver.bb` |
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
# The broken driver has NO of_match_table:
cat ~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/files/kotesh_of_driver.c
# Notice: no of_match_table in platform_driver struct

# Boot QEMU and observe:
dmesg | grep -i "KOTESH_OF"   # no output
lsmod | grep kotesh_of        # module loaded
ls /sys/bus/platform/drivers/kotesh_of/  # driver registered
# but device and driver never bound!

# Fix: add of_match_table to driver
# Rebuild, reboot — probe called
```

---

## ✅ Key Difference vs Issue 01 (Compatible Mismatch)

| | Issue 01 — Compatible Mismatch | Issue 08 — Missing of_match_table |
|---|---|---|
| `of_match_table` present | ✅ Yes | ❌ No |
| compatible string correct | ❌ Wrong string | ✅ Correct in DTS |
| Probe called | ❌ No | ❌ No |
| Error in dmesg | None | None |
| Driver in `/sys/bus/platform/drivers/` | ✅ Yes | ✅ Yes |
| Fix | Fix compatible string | Add `of_match_table` to driver |

---

## 📌 CONFIG_OF Related Kernel Config

```
CONFIG_OF=y              # Enable Device Tree support (mandatory for DT boards)
CONFIG_OF_ADDRESS=y      # Enable of_address APIs (reg property parsing)
CONFIG_OF_IRQ=y          # Enable of_irq APIs (interrupts property parsing)
CONFIG_OF_CLKDEV=y       # Enable clock device binding via DT
```

If `CONFIG_OF=n`, all `of_*` functions become stubs returning NULL/error,
and `of_match_table` is ignored entirely — no DT-based driver matching works.
```

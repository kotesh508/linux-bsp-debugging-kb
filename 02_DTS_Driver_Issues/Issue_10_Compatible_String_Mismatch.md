# Issue 10 — Multiple Drivers Matching Same Compatible String (Driver Conflict)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Two drivers both declare the same `compatible` string. Both modules load and both drivers register, but only **one driver probes** — whichever loads first wins. The second driver is silently ignored:

```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_MULTI"
[    7.063561] KOTESH_MULTI_A: probe called!
[    7.063997] KOTESH_MULTI_A: I am driver A - probe successful
# Driver B never probed!

root@qemuarm64:~# lsmod | grep kotesh_multi
kotesh_multi_b 16384 0 - Live 0xffffffc000bc8000 (O)
kotesh_multi_a 16384 0 - Live 0xffffffc000bb0000 (O)
# Both loaded but only A probed!

root@qemuarm64:~# ls /sys/bus/platform/devices/20005000.kotesh-multi/driver
# -> ../../../bus/platform/drivers/kotesh_multi_a
# Device bound to A only!
```

---

## 🔍 Stage Identification

**Stage:** Driver-device binding stage  
Both drivers register successfully with the platform bus. The first driver to register wins the device binding. The second driver registers but finds the device already claimed — it never probes.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg — only driver A probed
dmesg | grep -i "KOTESH_MULTI"
# KOTESH_MULTI_A: probe called!
# KOTESH_MULTI_A: I am driver A - probe successful
# (no KOTESH_MULTI_B output!)

# 2. Both drivers registered
ls /sys/bus/platform/drivers/ | grep kotesh_multi
# kotesh_multi_a
# kotesh_multi_b

# 3. Both modules loaded
lsmod | grep kotesh_multi
# kotesh_multi_b 16384 0 - Live ...
# kotesh_multi_a 16384 0 - Live ...

# 4. Check which driver won — KEY CHECK
cat /sys/bus/platform/devices/20005000.kotesh-multi/uevent
# DRIVER=kotesh_multi_a   ← A won!

# 5. Check driver symlink
ls -la /sys/bus/platform/devices/20005000.kotesh-multi/driver
# -> .../drivers/kotesh_multi_a   ← bound to A only
```

---

## 🔍 Root Cause

Both drivers declared **identical compatible strings**:

```c
/* Driver A */
static const struct of_device_id kotesh_multi_a_ids[] = {
    { .compatible = "kotesh,multi-driver" },   /* SAME! */
    { }
};

/* Driver B */
static const struct of_device_id kotesh_multi_b_ids[] = {
    { .compatible = "kotesh,multi-driver" },   /* SAME! */
    { }
};
```

**How Linux resolves this conflict:**
1. Both drivers register on platform bus
2. First driver to register (`kotesh_multi_a`) matches the device
3. Device is bound to driver A — `probe()` called
4. Driver B registers but device is already bound
5. Driver B never probes — silently ignored
6. **Last-loaded driver does NOT override** — first-bound wins

This is a real-world issue when:
- Two BSP vendors provide drivers for the same hardware
- A driver is duplicated in two different kernel modules
- An upstream driver and a vendor driver both claim the same compatible

---

## ✅ Fix

### Option 1: Remove the duplicate driver
Keep only one driver. Remove the conflicting recipe from the image:

```bitbake
# core-image-minimal.bbappend
# Remove or comment out one of the conflicting drivers
IMAGE_INSTALL += "kotesh-multi-driver-a"
# IMAGE_INSTALL += "kotesh-multi-driver-b"  ← remove this
```

### Option 2: Use unique compatible strings
Each driver should have a unique compatible string:

```c
/* Driver A — specific hardware version */
{ .compatible = "kotesh,multi-driver-v1" },

/* Driver B — different hardware version */
{ .compatible = "kotesh,multi-driver-v2" },
```

And DTS selects the correct one:
```dts
kotesh-multi@20005000 {
    compatible = "kotesh,multi-driver-v1";   /* selects driver A */
    reg = <0x0 0x20005000 0x0 0x1000>;
    status = "okay";
};
```

### Option 3: Use compatible string list (fallback chain)
DTS can list multiple compatible strings — kernel tries most specific first:

```dts
kotesh-multi@20005000 {
    compatible = "kotesh,multi-driver-v2", "kotesh,multi-driver";
    /* tries v2 first, falls back to generic */
};
```

---

## 🧠 Interview Explanation

> When two kernel drivers declare the same `compatible` string in their `of_match_table`, both register on the platform bus but only the first one to register gets to probe the device. The second driver silently never probes. This is a common issue in BSP development when a vendor tree has both an upstream driver and a custom vendor driver claiming the same hardware. The kernel does not report an error — it just silently uses the first driver. Diagnosis involves checking `/sys/bus/platform/devices/<dev>/driver` to see which driver won, and `dmesg` to see which probe was called. The fix is to either remove the duplicate driver, use unique compatible strings per hardware revision, or use a compatible string list in DTS to select the preferred driver.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver A source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-multi-driver/files/kotesh_multi_a.c` |
| Driver B source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-multi-driver/files/kotesh_multi_b.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-multi-driver/kotesh-multi-driver.bb` |
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
# Two drivers with same compatible string already in:
# kotesh_multi_a.c — compatible = "kotesh,multi-driver"
# kotesh_multi_b.c — compatible = "kotesh,multi-driver"

# DTS node
# kotesh-multi@20005000 { compatible = "kotesh,multi-driver"; ... }

# Boot QEMU and observe:
dmesg | grep -i "KOTESH_MULTI"
# Only A probes — B is silently ignored

# Check which driver won
cat /sys/bus/platform/devices/20005000.kotesh-multi/uevent | grep DRIVER
# DRIVER=kotesh_multi_a

# Fix: use unique compatible strings or remove duplicate driver
```

---

## ✅ Complete DTS Issues Summary

| Issue | Root Cause | Probe Called? | Error in dmesg? | Key Diagnostic |
|---|---|---|---|---|
| 01 | Compatible mismatch | ❌ No | ❌ None | `cat /proc/device-tree/<node>/compatible` |
| 02 | `status = "disabled"` | ❌ No | ❌ None | `cat /proc/device-tree/<node>/status` |
| 03 | Missing `reg` | ✅ Fails | ✅ error -22 | `ls /proc/device-tree/<node>/` |
| 04 | Wrong IRQ number | ✅ Fails | ✅ Resource unavailable | `cat /proc/interrupts` |
| 05 | Probe deferral | ❌ Deferred | ❌ None | `cat /sys/kernel/debug/devices_deferred` |
| 06 | Missing clock | ✅ Fails | ✅ error -2 | `ls /proc/device-tree/<node>/` |
| 07 | Missing regulator | ✅ Fails | ✅ error -19 | `ls /proc/device-tree/<node>/` |
| 08 | Missing `of_match_table` | ❌ No | ❌ None | `ls /sys/bus/platform/drivers/<drv>/` |
| 09 | Driver not in image | ❌ No | ❌ None | `find /lib/modules -name "*.ko"` |
| 10 | Duplicate compatible | ⚠️ Only first | ❌ None | `cat /sys/bus/platform/devices/<dev>/uevent` |

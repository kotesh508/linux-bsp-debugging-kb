# Issue 09 — Device Present in DTS but Driver Not in Image

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

DTS node exists, platform device is created, but **no driver is registered and probe is never called**. Zero error messages:

```bash
root@qemuarm64:~# ls /proc/device-tree/kotesh-of@20004000/
compatible  name  reg  status
# Node exists in device tree ✅

root@qemuarm64:~# ls /sys/bus/platform/devices/ | grep kotesh-of
20004000.kotesh-of
# Platform device created ✅

root@qemuarm64:~# find /lib/modules -name "kotesh_of*"
# (no output) — module not in rootfs ❌

root@qemuarm64:~# ls /sys/bus/platform/drivers/ | grep kotesh_of
# (no output) — driver never registered ❌

root@qemuarm64:~# dmesg | grep -i "KOTESH_OF"
# (no output) — probe never called ❌
```

---

## 🔍 Stage Identification

**Stage:** Rootfs / image packaging stage  
The kernel correctly parsed the DTB and created a platform device, but the driver module (`.ko`) was never built or included in the rootfs image. Without the module present, the driver is never loaded and probe is never called.

---

## 🔎 What I Checked

```bash
# 1. Confirm DTS node exists
ls /proc/device-tree/kotesh-of@20004000/
# compatible  name  reg  status ✅

# 2. Confirm platform device was created
ls /sys/bus/platform/devices/ | grep kotesh-of
# 20004000.kotesh-of ✅

# 3. Check if module exists in rootfs — KEY CHECK
find /lib/modules -name "kotesh_of*"
# (empty) ❌ — module not installed

# 4. Check if driver is registered
ls /sys/bus/platform/drivers/ | grep kotesh_of
# (empty) ❌ — driver never loaded

# 5. Check dmesg
dmesg | grep -i "KOTESH_OF"
# (empty) ❌ — probe never called

# 6. Check autoload config
ls /etc/modules-load.d/
# kotesh_of_driver.conf missing
```

---

## 🔍 Root Cause

The driver recipe was **not included in the image**. The `IMAGE_INSTALL` line was missing or commented out in the image bbappend:

```bitbake
# core-image-minimal.bbappend — BROKEN
IMAGE_INSTALL += "my-dummy-driver"
IMAGE_INSTALL += "kotesh-reg-driver"
IMAGE_INSTALL += "kotesh-irq-driver"
IMAGE_INSTALL += "kotesh-clk-driver"
IMAGE_INSTALL += "kotesh-reg-vcc-driver"
# IMAGE_INSTALL += "kotesh-of-driver"   ← commented out!
```

This means:
1. The DTS node is present → kernel creates platform device ✅
2. The `.ko` file is missing from `/lib/modules/` ❌
3. No module to load → no driver registered ❌
4. No driver → no probe ❌

**This is a very common real-world BSP issue:**
- Developer adds DTS node for new hardware
- Forgets to add driver recipe to image
- Device boots, hardware is enumerated, but driver never loads
- No error messages — completely silent failure

---

## ✅ Fix

Add the driver recipe back to `IMAGE_INSTALL` in the image bbappend:

```bitbake
# core-image-minimal.bbappend — FIXED
IMAGE_INSTALL += "my-dummy-driver"
IMAGE_INSTALL += "kotesh-reg-driver"
IMAGE_INSTALL += "kotesh-irq-driver"
IMAGE_INSTALL += "kotesh-clk-driver"
IMAGE_INSTALL += "kotesh-reg-vcc-driver"
IMAGE_INSTALL += "kotesh-of-driver"    ← uncommented!
```

Rebuild image:
```bash
cd ~/yocto/poky
source oe-init-build-env build
MACHINE=qemuarm64 bitbake core-image-minimal
```

**Verification after fix:**
```bash
# Module present in rootfs
find /lib/modules -name "kotesh_of*"
# /lib/modules/5.15.194-yocto-standard/extra/kotesh_of_driver.ko ✅

# Driver registered
ls /sys/bus/platform/drivers/ | grep kotesh_of
# kotesh_of ✅
```

---

## 🧠 Interview Explanation

> In embedded Linux, the DTS describes the hardware and the kernel uses it to create platform devices at boot. However, just having a DTS node does not guarantee the driver will run — the driver module must also be present in the rootfs. In Yocto, this requires the driver recipe to be added to `IMAGE_INSTALL` in the image recipe or bbappend. If this is missing, the kernel creates the platform device but no driver ever loads. The result is a completely silent failure — no error messages, no dmesg output. Diagnosis involves checking `/lib/modules/` for the `.ko` file, checking `/sys/bus/platform/drivers/` for driver registration, and verifying the image bbappend has the correct `IMAGE_INSTALL` entry.

---

## 📁 Related Files

| File | Path |
|------|------|
| Image bbappend | `~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend` |
| Driver recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-of-driver/kotesh-of-driver.bb` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |

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
# Step 1: Comment out driver from image bbappend
nano ~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend
# Change: IMAGE_INSTALL += "kotesh-of-driver"
# To:   # IMAGE_INSTALL += "kotesh-of-driver"

# Step 2: Rebuild image
MACHINE=qemuarm64 bitbake core-image-minimal

# Step 3: Boot QEMU (command above)

# Step 4: Observe broken state
find /lib/modules -name "kotesh_of*"          # empty
ls /sys/bus/platform/drivers/ | grep kotesh   # kotesh_of missing
dmesg | grep -i "KOTESH_OF"                   # no output

# Step 5: Fix — uncomment IMAGE_INSTALL line
# Rebuild, reboot — module present, probe called
```

---

## ✅ Diagnosis Checklist for "Device present, driver not loading"

```bash
# Step 1: Is the DTS node present?
ls /proc/device-tree/<node-name>/
# If missing → DTS/DTB problem

# Step 2: Is the platform device created?
ls /sys/bus/platform/devices/ | grep <device>
# If missing → DTS compatible or status problem

# Step 3: Is the module in rootfs?
find /lib/modules -name "<driver>*.ko"
# If missing → IMAGE_INSTALL missing in bbappend ← Issue 09

# Step 4: Is the driver registered?
ls /sys/bus/platform/drivers/ | grep <driver>
# If missing → module not loaded (check /etc/modules-load.d/)

# Step 5: Is probe called?
dmesg | grep -i "<driver>"
# If missing → compatible mismatch or other probe issue
```

---

## 📌 Comparison — Silent Failures

| Issue | Root Cause | Module in `/lib/modules`? | Driver in `/sys/bus/platform/drivers/`? |
|---|---|---|---|
| Issue 08 | Missing `of_match_table` | ✅ Yes | ✅ Yes (but unbound) |
| Issue 09 | Driver not in image | ❌ No | ❌ No |
| Issue 01 | Compatible mismatch | ✅ Yes | ✅ Yes (but unbound) |

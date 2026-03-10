# Issue 03 — Missing `reg` Property (Memory Resource Not Found)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver probe is called but **fails with error -22 (EINVAL)** because it cannot get the memory resource.

```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_REG"
[    6.960222] kotesh_reg_driver: loading out-of-tree module taints kernel.
[    7.020712] KOTESH_REG: failed to get memory resource
[    7.021339] kotesh_reg: probe of kotesh-reg failed with error -22

root@qemuarm64:~# ls /proc/device-tree/kotesh-reg/
compatible  name  status
# Note: no "reg" entry here!

root@qemuarm64:~# ls /sys/bus/platform/devices/ | grep kotesh
kotesh-dummy
kotesh-reg        # device registered but probe failed
```

**Error -22 = EINVAL = Invalid Argument** — returned by the driver when `platform_get_resource()` returns NULL.

---

## 🔍 Stage Identification

**Stage:** Driver probe stage  
Unlike Issue 01 and Issue 02 where probe is never called, here probe **is called** but fails midway because a required hardware resource (`reg`) is missing from the DTS node.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg for error
dmesg | grep -i "KOTESH_REG"
# KOTESH_REG: failed to get memory resource
# kotesh_reg: probe of kotesh-reg failed with error -22

# 2. Check device tree node — reg property missing
ls /proc/device-tree/kotesh-reg/
# compatible  name  status   (no "reg" file!)

# 3. Check platform devices — device exists but probe failed
ls /sys/bus/platform/devices/ | grep kotesh
# kotesh-reg present but not functional

# 4. Check module loaded
lsmod | grep kotesh_reg
```

---

## 🔍 Root Cause

The DTS node was **missing the `reg` property**:

```dts
/* BROKEN — missing reg property */
kotesh-reg {
    compatible = "kotesh,reg-driver";
    /* reg = <0x0 0x10000000 0x0 0x1000>; */
    status = "okay";
};
```

The driver called `platform_get_resource()` to get the memory region:

```c
res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
if (!res) {
    pr_err("KOTESH_REG: failed to get memory resource\n");
    return -EINVAL;
}
```

When `reg` is missing from the DTS node, the kernel has no memory region to pass to the driver. `platform_get_resource()` returns `NULL`, the driver returns `-EINVAL`, and probe fails.

The `reg` property defines the **physical memory address and size** of the device's register space. Format for a 64-bit system (`#address-cells = <2>`, `#size-cells = <2>`):

```dts
reg = <addr_hi addr_lo size_hi size_lo>;
reg = <0x0 0x10000000 0x0 0x1000>;
/*     ^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^
       start addr = 0x10000000   size = 0x1000 (4KB) */
```

---

## ✅ Fix

Add the `reg` property back to the DTS node:

```dts
/* FIXED */
kotesh-reg@10000000 {
    compatible = "kotesh,reg-driver";
    reg = <0x0 0x10000000 0x0 0x1000>;
    status = "okay";
};
```

Recompile DTB:
```bash
dtc -I dts -O dtb -o /home/kotesh/dtstest/kotesh-test.dtb \
    /home/kotesh/dtstest/qemu-virt.dts
```

**Verification after fix:**
```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_REG"
[    6.866715] KOTESH_REG: probe successful
[    6.867170] KOTESH_REG: memory region start=0x10000000 size=0x1000

root@qemuarm64:~# ls /proc/device-tree/kotesh-reg/
compatible  name  reg  status
```

---

## 🧠 Interview Explanation

> The `reg` property in a Device Tree node describes the physical memory address and size of a device's register space. When a driver calls `platform_get_resource(pdev, IORESOURCE_MEM, 0)`, the kernel translates the `reg` property from the DTS into a `struct resource` and returns it. If the `reg` property is missing, `platform_get_resource()` returns NULL. A well-written driver checks for this and returns `-EINVAL`, causing probe to fail with `error -22`. The fix is to add the correct `reg` property matching the device's actual hardware address range. This is different from a compatible mismatch or disabled node — in those cases probe is never called at all, but here probe is called and fails midway.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-reg-driver/files/kotesh_reg_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-reg-driver/kotesh-reg-driver.bb` |
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
# Step 1: Remove reg property from DTS node
nano ~/dtstest/qemu-virt.dts
# Comment out: /* reg = <0x0 0x10000000 0x0 0x1000>; */

# Step 2: Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# Step 3: Boot QEMU (use command above)

# Step 4: Check broken state
dmesg | grep -i "KOTESH_REG"
# KOTESH_REG: failed to get memory resource
# kotesh_reg: probe of kotesh-reg failed with error -22

ls /proc/device-tree/kotesh-reg/
# compatible  name  status   (no reg!)

# Step 5: Fix — add reg back
# reg = <0x0 0x10000000 0x0 0x1000>;
# Recompile, reboot — probe succeeds
```

---

## ✅ Working State Verification

```bash
# All 4 checks must pass:

# 1. reg property present in device tree
ls /proc/device-tree/kotesh-reg/
# compatible  name  reg  status

# 2. Probe successful with memory info printed
dmesg | grep KOTESH_REG
# [    6.866715] KOTESH_REG: probe successful
# [    6.867170] KOTESH_REG: memory region start=0x10000000 size=0x1000

# 3. Module loaded
lsmod | grep kotesh_reg
# kotesh_reg_driver 16384 0 - Live ...

# 4. Device registered with address
ls /sys/bus/platform/devices/ | grep kotesh
# 10000000.kotesh-reg
```

---

## 📌 Comparison — Issue 01 vs 02 vs 03

| | Issue 01 | Issue 02 | Issue 03 |
|---|---|---|---|
| Root cause | Wrong `compatible` | `status = "disabled"` | Missing `reg` |
| Probe called | ❌ Never | ❌ Never | ✅ Called but fails |
| Error in dmesg | No output | No output | `probe failed with error -22` |
| Device in `/sys/bus/platform/devices/` | ❌ No | ❌ No | ✅ Present but broken |
| Node in `/proc/device-tree/` | ✅ Yes | ✅ Yes | ✅ Yes |
| Fix | Match compatible string | Change to `"okay"` | Add `reg` property |

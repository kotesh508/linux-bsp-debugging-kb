# Issue 06 — Missing Clock Property (devm_clk_get fails)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver probe is called but fails with **error -2 (ENOENT)** because the clock property is missing from the DTS node:

```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_CLK"
[    7.232972] KOTESH_CLK: probe called
[    7.234111] KOTESH_CLK: failed to get clock, error=-2
[    7.234770] kotesh_clk: probe of 20002000.kotesh-clk failed with error -2

root@qemuarm64:~# ls /proc/device-tree/kotesh-clk@20002000/
compatible  name  reg  status
# Note: no "clocks" or "clock-names" entries!
```

**Error -2 = ENOENT = No such file or directory** — the clock provider was not found.

---

## 🔍 Stage Identification

**Stage:** Driver probe stage  
Probe is called successfully but fails midway when `devm_clk_get()` cannot find the clock because the `clocks` property is missing from the DTS node.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg for clock error
dmesg | grep -i "KOTESH_CLK"
# KOTESH_CLK: failed to get clock, error=-2
# kotesh_clk: probe of 20002000.kotesh-clk failed with error -2

# 2. Check device tree node — clocks property missing
ls /proc/device-tree/kotesh-clk@20002000/
# compatible  name  reg  status
# (no "clocks" or "clock-names"!)

# 3. Check platform device exists
ls /sys/bus/platform/devices/ | grep kotesh-clk
# 20002000.kotesh-clk  present but probe failed

# 4. Check working state node has clocks
ls /proc/device-tree/kotesh-clk@20002000/
# clock-names  clocks  compatible  name  reg  status
```

---

## 🔍 Root Cause

The DTS node was missing the `clocks` and `clock-names` properties:

```dts
/* BROKEN — missing clock properties */
kotesh-clk@20002000 {
    compatible = "kotesh,clk-driver";
    reg = <0x0 0x20002000 0x0 0x1000>;
    /* clocks = <0x8000>; */          /* removed! */
    /* clock-names = "apb_pclk"; */   /* removed! */
    status = "okay";
};
```

The driver called `devm_clk_get()` to get the clock:

```c
clk = devm_clk_get(&pdev->dev, NULL);
if (IS_ERR(clk)) {
    pr_err("KOTESH_CLK: failed to get clock, error=%ld\n", PTR_ERR(clk));
    return PTR_ERR(clk);
}
```

When `clocks` is missing from the DTS node, `devm_clk_get()` returns `-ENOENT` (error -2) because there is no clock provider registered for this device. Probe fails and returns `-ENOENT`.

**How `clocks` property works:**
```dts
clocks = <0x8000>;          /* phandle of clock provider */
clock-names = "apb_pclk";  /* name used in driver to request clock */
```

The phandle `0x8000` points to the `apb-pclk` fixed clock node:
```dts
apb-pclk {
    phandle = <0x8000>;
    clock-output-names = "clk24mhz";
    clock-frequency = <0x16e3600>;   /* 24MHz */
    #clock-cells = <0x00>;
    compatible = "fixed-clock";
};
```

---

## ✅ Fix

Add the `clocks` and `clock-names` properties back to the DTS node:

```dts
/* FIXED */
kotesh-clk@20002000 {
    compatible = "kotesh,clk-driver";
    reg = <0x0 0x20002000 0x0 0x1000>;
    clocks = <0x8000>;              /* phandle of apb-pclk */
    clock-names = "apb_pclk";      /* name to request in driver */
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
root@qemuarm64:~# dmesg | grep -i "KOTESH_CLK"
[    6.922211] KOTESH_CLK: probe called
[    6.922761] KOTESH_CLK: got clock successfully
[    6.923185] KOTESH_CLK: probe successful

root@qemuarm64:~# ls /proc/device-tree/kotesh-clk@20002000/
clock-names  clocks  compatible  name  reg  status
```

---

## 🧠 Interview Explanation

> The `clocks` property in a DTS node specifies which clock provider the device uses, referenced by phandle. The `clock-names` property gives each clock a name so the driver can request it by name using `devm_clk_get(&pdev->dev, "name")`. When the `clocks` property is missing, `devm_clk_get()` returns `-ENOENT` (error -2) because the kernel cannot find any clock registered for that device. This is a common issue in BSP bring-up when porting a driver to a new board — the driver works on the reference board but fails on the custom board because the custom DTS is missing the clock binding. The fix is to identify the correct clock provider phandle from the DTS and add the `clocks` and `clock-names` properties to the device node.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-clk-driver/files/kotesh_clk_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-clk-driver/kotesh-clk-driver.bb` |
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
# Step 1: Remove clocks property from DTS node
nano ~/dtstest/qemu-virt.dts
# Comment out:
# /* clocks = <0x8000>; */
# /* clock-names = "apb_pclk"; */

# Step 2: Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# Step 3: Boot QEMU (command above)

# Step 4: Observe broken state
dmesg | grep -i "KOTESH_CLK"
# KOTESH_CLK: failed to get clock, error=-2
# kotesh_clk: probe of 20002000.kotesh-clk failed with error -2

ls /proc/device-tree/kotesh-clk@20002000/
# compatible  name  reg  status  (no clocks!)

# Step 5: Fix — add clocks properties back
# clocks = <0x8000>;
# clock-names = "apb_pclk";
# Recompile, reboot — probe succeeds
```

---

## ✅ Working State Verification

```bash
# All checks must pass:

# 1. Clock properties present in device tree
ls /proc/device-tree/kotesh-clk@20002000/
# clock-names  clocks  compatible  name  reg  status

# 2. Probe successful
dmesg | grep KOTESH_CLK
# KOTESH_CLK: probe called
# KOTESH_CLK: got clock successfully
# KOTESH_CLK: probe successful

# 3. Device registered
ls /sys/bus/platform/devices/ | grep kotesh-clk
# 20002000.kotesh-clk
```

---

## 📌 Common Clock Errors

| Error Code | Meaning | Cause |
|---|---|---|
| `-2` (ENOENT) | Clock not found | Missing `clocks` property in DTS |
| `-517` (EPROBE_DEFER) | Clock provider not ready yet | Clock driver not yet probed |
| `-22` (EINVAL) | Invalid clock | Wrong phandle or `#clock-cells` mismatch |

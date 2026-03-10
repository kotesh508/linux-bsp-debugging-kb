# Issue 07 — Missing Regulator Property (devm_regulator_get fails)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver probe is called but fails with **error -19 (ENODEV)** because the regulator supply property is missing from the DTS node:

```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_VCC"
[    6.930085] KOTESH_VCC: probe called
[    6.930654] KOTESH_VCC: failed to get regulator, error=-19
# No "probe successful" line!

root@qemuarm64:~# ls /proc/device-tree/kotesh-vcc@20003000/
compatible  name  reg  status
# Note: no "vcc-supply" entry!
```

**Error -19 = ENODEV = No such device** — regulator provider not found.

---

## 🔍 Stage Identification

**Stage:** Driver probe stage  
Probe is called successfully but fails when `devm_regulator_get_optional()` cannot find the regulator because the `vcc-supply` property is missing from the DTS node.

---

## 🔎 What I Checked

```bash
# 1. Check dmesg for regulator error
dmesg | grep -i "KOTESH_VCC"
# KOTESH_VCC: probe called
# KOTESH_VCC: failed to get regulator, error=-19

# 2. Check device tree node — vcc-supply missing
ls /proc/device-tree/kotesh-vcc@20003000/
# compatible  name  reg  status
# (no "vcc-supply"!)

# 3. Check platform device exists
ls /sys/bus/platform/devices/ | grep kotesh-vcc
# 20003000.kotesh-vcc  present but probe failed
```

---

## 🔍 Root Cause

The DTS node was missing the `vcc-supply` property:

```dts
/* BROKEN — missing regulator supply */
kotesh-vcc@20003000 {
    compatible = "kotesh,regulator-driver";
    reg = <0x0 0x20003000 0x0 0x1000>;
    /* vcc-supply = <0x8000>; */    /* removed! */
    status = "okay";
};
```

The driver called `devm_regulator_get_optional()`:

```c
vcc = devm_regulator_get_optional(&pdev->dev, "vcc");
if (IS_ERR(vcc)) {
    pr_err("KOTESH_VCC: failed to get regulator, error=%ld\n",
           PTR_ERR(vcc));
    return PTR_ERR(vcc);
}
```

When `vcc-supply` is missing, `devm_regulator_get_optional()` returns `-ENODEV`
because there is no regulator provider registered for this device.

**Important distinction between regulator get functions:**

| Function | Missing supply behavior |
|---|---|
| `devm_regulator_get()` | Returns **dummy regulator** — probe succeeds silently! |
| `devm_regulator_get_optional()` | Returns `-ENODEV` — probe fails visibly |
| `devm_regulator_get_exclusive()` | Returns `-ENODEV` — probe fails visibly |

This is why `devm_regulator_get()` masked the issue — it silently provides a
dummy regulator even when `vcc-supply` is missing from DTS.

---

## ✅ Fix

Add the `vcc-supply` property back to the DTS node:

```dts
/* FIXED */
kotesh-vcc@20003000 {
    compatible = "kotesh,regulator-driver";
    reg = <0x0 0x20003000 0x0 0x1000>;
    vcc-supply = <0x8000>;      /* phandle of regulator provider */
    status = "okay";
};
```

The phandle `0x8000` points to `apb-pclk` fixed clock which acts as a
supply provider in our QEMU virt setup.

Recompile DTB:
```bash
dtc -I dts -O dtb -o /home/kotesh/dtstest/kotesh-test.dtb \
    /home/kotesh/dtstest/qemu-virt.dts
```

**Verification after fix:**
```bash
root@qemuarm64:~# dmesg | grep -i "KOTESH_VCC"
[    6.774723] KOTESH_VCC: probe called
[    6.775256] KOTESH_VCC: got regulator successfully
[    6.775771] KOTESH_VCC: probe successful

root@qemuarm64:~# ls /proc/device-tree/kotesh-vcc@20003000/
compatible  name  reg  status  vcc-supply
```

---

## 🧠 Interview Explanation

> The `vcc-supply` property in a DTS node specifies which voltage regulator powers the device, referenced by phandle. The driver requests this regulator using `devm_regulator_get()` or `devm_regulator_get_optional()`. A critical difference: `devm_regulator_get()` silently returns a dummy regulator when the supply is missing — probe succeeds but the device may behave incorrectly at runtime. `devm_regulator_get_optional()` returns `-ENODEV` when the supply is missing, making the failure visible. This is a common BSP issue — the driver works on the reference platform but silently fails on a custom board with missing regulator bindings. Always use `devm_regulator_get_optional()` for supplies that are truly optional, and `devm_regulator_get()` only for mandatory supplies where you want a dummy fallback.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-reg-vcc-driver/files/kotesh_reg_vcc_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-reg-vcc-driver/kotesh-reg-vcc-driver.bb` |
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
# Step 1: Remove vcc-supply from DTS node
nano ~/dtstest/qemu-virt.dts
# Comment out: /* vcc-supply = <0x8000>; */

# Step 2: Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# Step 3: Boot QEMU (command above)

# Step 4: Observe broken state
dmesg | grep -i "KOTESH_VCC"
# KOTESH_VCC: failed to get regulator, error=-19

ls /proc/device-tree/kotesh-vcc@20003000/
# compatible  name  reg  status  (no vcc-supply!)

# Step 5: Fix — add vcc-supply back
# vcc-supply = <0x8000>;
# Recompile, reboot — probe succeeds
```

---

## ✅ Working State Verification

```bash
# All checks must pass:

# 1. vcc-supply present in device tree
ls /proc/device-tree/kotesh-vcc@20003000/
# compatible  name  reg  status  vcc-supply

# 2. Probe successful
dmesg | grep KOTESH_VCC
# KOTESH_VCC: probe called
# KOTESH_VCC: got regulator successfully
# KOTESH_VCC: probe successful

# 3. Device registered
ls /sys/bus/platform/devices/ | grep kotesh-vcc
# 20003000.kotesh-vcc
```

 # Issue 01 — Compatible String Mismatch (Driver Not Probed)

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Driver module loads successfully but `probe()` is never called.

```
root@qemuarm64:~# lsmod | grep my_dummy
my_dummy_driver 16384 0 - Live 0xffffffc000ba0000 (O)

root@qemuarm64:~# dmesg | grep MY_DUMMY
(no output)
```

No `MY_DUMMY: probe successful` in dmesg even though the module is loaded.

---

## 🔍 Stage Identification

**Stage:** Post-boot, driver binding stage  
The kernel has booted and loaded the module, but the Device Tree node and driver are not being matched.

---

## 🔎 What I Checked

```bash
# 1. Confirmed module is loaded
lsmod | grep my_dummy

# 2. Checked dmesg for probe message
dmesg | grep -i "MY_DUMMY"

# 3. Verified DTB node exists
ls /proc/device-tree/kotesh-dummy/
cat /proc/device-tree/kotesh-dummy/compatible

# 4. Checked platform drivers registered
ls /sys/bus/platform/drivers/

# 5. Checked if driver appears in platform drivers
ls /sys/bus/platform/drivers/ | grep dummy
```

---

## 🔍 Root Cause

The `compatible` string in the DTS node did **not match** the `compatible` string in the driver's `of_match_table`.

**Driver code had:**
```c
static const struct of_device_id my_dummy_ids[] = {
    { .compatible = "kotesh,mydummy" },
    { }
};
```

**DTS node had (wrong):**
```dts
kotesh-dummy {
    compatible = "kotesh,my-dummy";   /* <-- mismatch! hyphen vs no hyphen */
    status = "okay";
};
```

The kernel does an **exact string match** between the DTS `compatible` property and the driver's `of_match_table`. Even a single character difference (hyphen, underscore, capital letter) causes probe to never be called.

---

## ✅ Fix

Make the `compatible` string **identical** in both places.

**DTS node (fixed):**
```dts
kotesh-dummy {
    compatible = "kotesh,mydummy";   /* exact match with driver */
    status = "okay";
};
```

**Driver (unchanged — this was correct):**
```c
static const struct of_device_id my_dummy_ids[] = {
    { .compatible = "kotesh,mydummy" },
    { }
};
MODULE_DEVICE_TABLE(of, my_dummy_ids);
```

Recompile DTB and reboot:
```bash
dtc -I dts -O dtb -o /home/kotesh/dtstest/kotesh-test.dtb \
    /home/kotesh/dtstest/qemu-virt.dts
```

**Verification after fix:**
```bash
root@qemuarm64:~# dmesg | grep MY_DUMMY
[    7.100753] MY_DUMMY: probe successful
```

---

## 🧠 Interview Explanation

> The Linux kernel matches a Device Tree node to a platform driver using the `compatible` string. The kernel walks the `of_match_table` in the driver and compares each entry against the `compatible` property in the DTS node using an **exact string match**. If there is any mismatch — even a hyphen vs underscore — the driver's `probe()` function is never called. The fix is to ensure the `compatible` string is byte-for-byte identical in both the DTS node and the driver's `of_device_id` table. Convention is `"vendor,device"` in lowercase with no spaces.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/my-dummy-driver/files/my_dummy_driver.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Compiled DTB | `~/dtstest/kotesh-test.dtb` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/my-dummy-driver/my-dummy-driver.bb` |
| Image append | `~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend` |

---

## 🧪 How to Reproduce

```bash
# 1. Change compatible in DTS to a wrong value
# Edit ~/dtstest/qemu-virt.dts:
#   compatible = "kotesh,wrong-string";

# 2. Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# 3. Boot QEMU and check — probe will NOT be called
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
  
dmesg | grep MY_DUMMY   # no output

# 4. Fix compatible string back to "kotesh,mydummy"
# Recompile, reboot — probe WILL be called
dmesg | grep MY_DUMMY   # MY_DUMMY: probe successful
```

---

## ✅ Working State Verification

```bash
# All 4 checks must pass:

# 1. DTB node present
ls /proc/device-tree/kotesh-dummy/
# compatible  name  status

# 2. Compatible string correct
cat /proc/device-tree/kotesh-dummy/compatible
# kotesh,mydummy

# 3. Module loaded
lsmod | grep my_dummy
# my_dummy_driver 16384 0 - Live ...

# 4. Probe called
dmesg | grep MY_DUMMY
# [    7.100753] MY_DUMMY: probe successful
```

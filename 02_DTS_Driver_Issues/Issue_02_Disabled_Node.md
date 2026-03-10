# Issue 02 — Device Node Disabled (status = "disabled")

---

## 📋 Category
`02_DTS_Driver_Issues`

## 🔴 Symptom

Module loads successfully, DTS node exists, but `probe()` is never called and device does not appear in `/sys/bus/platform/devices/`.

```bash
root@qemuarm64:~# lsmod | grep my_dummy
my_dummy_driver 16384 0 - Live 0xffffffc000ba0000 (O)

root@qemuarm64:~# dmesg | grep -i "MY_DUMMY"
[    6.225895] my_dummy_driver: loading out-of-tree module taints kernel.
# No "probe successful" line!

root@qemuarm64:~# ls /sys/bus/platform/devices/ | grep kotesh
# (no output)
```

---

## 🔍 Stage Identification

**Stage:** Post-boot, Device Tree parsing stage  
The kernel parsed the DTB at boot time, saw `status = "disabled"` on the node, and skipped registering it as a platform device entirely. The driver never gets a chance to probe.

---

## 🔎 What I Checked

```bash
# 1. Confirmed module is loaded
lsmod | grep my_dummy

# 2. Checked dmesg — module loads but no probe
dmesg | grep -i "MY_DUMMY"

# 3. Read the status property directly from device tree
cat /proc/device-tree/kotesh-dummy/status
# output: disabled

# 4. Confirmed device not registered
ls /sys/bus/platform/devices/ | grep kotesh
# (no output)
```

---

## 🔍 Root Cause

The DTS node had `status = "disabled"`:

```dts
kotesh-dummy {
    compatible = "kotesh,mydummy";
    status = "disabled";        /* <-- kernel skips this node */
};
```

When the kernel parses the Device Tree at boot, it checks the `status` property of every node. If `status = "disabled"`, the kernel **does not register the device** with the platform bus. Since no platform device is created, the driver's `probe()` function is never called — even if the driver module is loaded and the `compatible` string matches perfectly.

This is intentional behavior — `status = "disabled"` is the standard DTS way to describe hardware that is physically present on the board but should not be used by the OS (e.g., a peripheral shared between two SoCs, or hardware reserved for a hypervisor).

---

## ✅ Fix

Change `status` from `"disabled"` to `"okay"`:

```dts
kotesh-dummy {
    compatible = "kotesh,mydummy";
    status = "okay";            /* <-- kernel registers this node */
};
```

Recompile DTB and reboot:
```bash
dtc -I dts -O dtb -o /home/kotesh/dtstest/kotesh-test.dtb \
    /home/kotesh/dtstest/qemu-virt.dts
```
# Boot again
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

**Verification after fix:**
```bash
root@qemuarm64:~# cat /proc/device-tree/kotesh-dummy/status
okay

root@qemuarm64:~# dmesg | grep -i "MY_DUMMY"
[    4.824147] my_dummy_driver: loading out-of-tree module taints kernel.
[    4.877957] MY_DUMMY: probe successful

root@qemuarm64:~# ls /sys/bus/platform/devices/ | grep kotesh
kotesh-dummy
```

---

## 🧠 Interview Explanation

> In the Linux Device Tree, the `status` property controls whether the kernel treats a node as active hardware. A value of `"okay"` tells the kernel to register the device on the platform bus and match it to a driver. A value of `"disabled"` causes the kernel to skip the node entirely during boot — no platform device is created, so the driver's `probe()` is never called even if the module is loaded and the `compatible` string matches. This is commonly used in BSPs to ship a single DTS for a board family and selectively enable only the peripherals present on each variant using overlays or board-specific `.dtsi` files.

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
# 1. Edit DTS node
nano ~/dtstest/qemu-virt.dts
# Change: status = "okay"  →  status = "disabled"

# 2. Recompile DTB
dtc -I dts -O dtb -o ~/dtstest/kotesh-test.dtb ~/dtstest/qemu-virt.dts

# 3. Boot QEMU and verify broken state
cat /proc/device-tree/kotesh-dummy/status   # disabled
dmesg | grep MY_DUMMY                        # no probe successful
ls /sys/bus/platform/devices/ | grep kotesh  # no output

# 4. Fix: change back to status = "okay"
# Recompile, reboot — all checks pass
```

---

## ✅ Working State Verification

```bash
# All 4 checks must pass:

# 1. Status is okay
cat /proc/device-tree/kotesh-dummy/status
# okay

# 2. Probe was called
dmesg | grep MY_DUMMY
# [    4.877957] MY_DUMMY: probe successful

# 3. Module loaded
lsmod | grep my_dummy
# my_dummy_driver 16384 0 - Live ...

# 4. Device registered on platform bus
ls /sys/bus/platform/devices/ | grep kotesh
# kotesh-dummy
```

---

## 📌 Key Difference vs Issue 01 (Compatible Mismatch)

| | Issue 01 — Compatible Mismatch | Issue 02 — Disabled Node |
|---|---|---|
| Node in `/proc/device-tree/` | ✅ Present | ✅ Present |
| Module loaded | ✅ Yes | ✅ Yes |
| Device in `/sys/bus/platform/devices/` | ❌ Missing | ❌ Missing |
| Probe called | ❌ No | ❌ No |
| Root cause | Wrong `compatible` string | `status = "disabled"` |
| Fix | Match compatible strings | Change to `status = "okay"` |

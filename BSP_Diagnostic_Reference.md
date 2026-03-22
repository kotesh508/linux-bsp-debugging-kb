# BSP Lab — Complete 30 Issues Diagnostic Reference
# Kotesh S | github.com/kotesh508
# Method: See error → Know what to check → Know the fix

---

## HOW TO USE THIS FILE

When QEMU boots and something is wrong:
1. Run `dmesg | grep -i "error\|fail\|warn\|kotesh"`
2. Find your error pattern in this file
3. Run the exact diagnostic command
4. Apply the fix

---

## ERROR CODE QUICK REFERENCE

```
error=-2   ENOENT   Property missing in DTS (clock, reg, compatible)
error=-19  ENODEV   Device not found (regulator, hardware absent)
error=-22  EINVAL   Wrong value in DTS (bad reg format, bad size)
error=-16  EBUSY    Resource already used by another driver
error=-12  ENOMEM   Out of memory
error=-11  EAGAIN   Probe deferred — waiting for dependency
```

Check any error number:
```bash
grep "define E" ~/30days_workWith_BSP/day1/linux-6.6/include/uapi/asm-generic/errno-base.h
```

---

## KERNEL CONFIG QUICK CHECK (run inside QEMU)

```bash
zcat /proc/config.gz | grep CONFIG_KASAN
zcat /proc/config.gz | grep CONFIG_DETECT_HUNG_TASK
zcat /proc/config.gz | grep CONFIG_PANIC_ON_OOPS
zcat /proc/config.gz | grep CONFIG_DEBUG_PAGEALLOC
```

---

## SESSION SETUP (run this first every time)

```bash
source ~/BSP-Lab/bsp-session.sh
```

---

# CATEGORY 1 — BOOT ISSUES (01–05)
# These issues = driver never loads or rootfs never mounts

---

## Boot Issue 01 — No Console Output

### Symptom
```
QEMU starts but screen is blank — no kernel messages
```

### What to check
```bash
# Check your QEMU -append line
# Must have: console=ttyAMA0 (ARM) or console=ttyS0 (x86)

# Check DTB is correct
file ~/dtstest/kotesh-test.dtb
# Should say: Device Tree Blob version 17

# Check kernel image exists
ls -lh /home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/Image
```

### Fix
```bash
# Add correct console to QEMU -append:
-append "console=ttyAMA0 root=/dev/vda rw"

# Rebuild DTB if modified recently:
dtc -I dts -O dtb -o $DTB $DTS
```

---

## Boot Issue 02 — Wrong Root Device

### Symptom
```
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

### What to check
```bash
# Check your QEMU drive setup
# Must match: root=/dev/vda (for virtio-blk)

# Check image file exists
ls -lh /home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4
```

### Fix
```bash
# Correct QEMU drive parameters:
-drive if=none,format=raw,file=<image.ext4>,id=hd0
-device virtio-blk-device,drive=hd0
-append "... root=/dev/vda rw"
```

---

## Boot Issue 03 — Ext4 Module Missing

### Symptom
```
EXT4-fs: unable to read superblock
mount: mounting /dev/vda on / failed
```

### What to check
```bash
# Inside QEMU after partial boot:
zcat /proc/config.gz | grep CONFIG_EXT4
# Should show: CONFIG_EXT4_FS=y (not =m)

# Check if ext4 is module or built-in
find /lib/modules -name "ext4.ko"
```

### Fix
```bash
# In Yocto kernel config, set:
CONFIG_EXT4_FS=y   # built-in, not module
# Rebuild: bitbake core-image-minimal
```

---

## Boot Issue 04 — Missing Block Driver

### Symptom
```
virtio: probe of virtio0 failed
No working controllers found
```

### What to check
```bash
zcat /proc/config.gz | grep VIRTIO_BLK
# Should show: CONFIG_VIRTIO_BLK=y
```

### Fix
```bash
# In kernel config:
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MMIO=y
```

---

## Boot Issue 05 — No Init Found

### Symptom
```
Run /sbin/init as init process
Kernel panic - not syncing: No working init found!
```

### What to check
```bash
# Check rootfs has init
ls /sbin/init
ls /bin/sh

# Check Yocto image type
# core-image-minimal must include sysvinit or busybox-inittab
```

### Fix
```bash
# Add to local.conf:
IMAGE_INSTALL += "sysvinit busybox"
# OR use correct init in -append:
-append "... rdinit=/linuxrc"   # for initramfs
-append "... init=/sbin/init"   # for ext4 rootfs
```

---

# CATEGORY 2 — DTS / DRIVER ISSUES (01–10)
# These issues = driver loads but probe fails or wrong behavior

---

## DTS Issue 01 — Compatible String Mismatch

### Symptom
```
# Driver loads but NO probe message in dmesg
lsmod shows driver loaded
dmesg shows NO "probe successful"
```

### What to check
```bash
# Step 1 — Check what DTS says
cat /proc/device-tree/kotesh-dummy/compatible

# Step 2 — Check what driver expects
# In driver .c file:
# static const struct of_device_id my_ids[] = {
#     { .compatible = "kotesh,mydummy" },  ← must EXACTLY match DTS
# };

# Step 3 — Compare them — even one character difference = no match
```

### Fix
```bash
# In qemu-virt.dts, fix compatible string to exactly match driver:
kotesh-dummy {
    compatible = "kotesh,mydummy";   # exact match
    status = "okay";
};
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 02 — Device Node Disabled

### Symptom
```
Driver loads. No probe called. No error in dmesg.
```

### What to check
```bash
cat /proc/device-tree/kotesh-dummy/status
# shows: disabled

ls /sys/bus/platform/devices/ | grep kotesh-dummy
# no output = device not registered
```

### Fix
```bash
# In qemu-virt.dts:
status = "okay";   # change from "disabled"
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 03 — Missing reg Property

### Symptom
```
KOTESH_REG: failed to get memory resource
kotesh_reg: probe of kotesh-reg failed with error -22
```

### What to check
```bash
ls /proc/device-tree/kotesh-reg@20000000/
# If no "reg" file in output → reg property missing in DTS

dmesg | grep KOTESH_REG
# error=-22 = EINVAL = invalid or missing reg
```

### Fix
```bash
# In qemu-virt.dts, add reg property:
kotesh-reg@20000000 {
    compatible = "kotesh,reg-driver";
    reg = <0x0 0x20000000 0x0 0x1000>;  # base_hi base_lo size_hi size_lo
    status = "okay";
};
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 04 — Wrong Interrupt Number

### Symptom
```
Probe not called OR system unstable after probe
```

### What to check
```bash
cat /proc/interrupts
# Look for SPI number — is it already taken?

dmesg | grep -i "irq\|interrupt\|KOTESH_IRQ"
# Check if IRQ request failed
```

### GIC interrupt format
```
interrupts = <type  number  trigger>
type:    0=SPI (shared), 1=PPI (per-cpu)
trigger: 1=edge-rising, 4=level-high
Linux IRQ = number + 32

Safe free SPIs on QEMU virt: 10, 11, 12, 13
Already used: 0x01(UART), 0x02(RTC), 0x07(GPIO)
```

### Fix
```bash
# Use a free SPI number:
interrupts = <0x0 0x0a 0x4>;   # SPI 10, level-high
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 05 — Probe Deferral

### Symptom
```
Driver loads. No probe called. No error.
```

### What to check
```bash
cat /sys/kernel/debug/devices_deferred
# If your device is listed here → deferred

ls /sys/bus/platform/devices/20001000.kotesh-irq/
# Look for: waiting_for_supplier file

dmesg | grep "KOTESH_IRQ"
# Only "module init" — no probe message
```

### Why it happens
```
interrupt-parent = <0x8001>  ← references cpu@0 phandle
cpu@0 has no interrupt-controller property
kernel waits forever for supplier that never comes
→ deferred forever
```

### Fix
```bash
# Option 1 — Use correct GIC phandle (0x8002 not 0x8001):
interrupt-parent = <0x8002>;   # GIC phandle

# Option 2 — Remove interrupt if not needed for testing:
# Delete interrupt-parent and interrupts lines
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 06 — Missing Clock Property

### Symptom
```
KOTESH_CLK: probe called
KOTESH_CLK: failed to get clock, error=-2
kotesh_clk: probe of 20002000.kotesh-clk failed with error -2
```

### What to check
```bash
ls /proc/device-tree/kotesh-clk@20002000/
# If no "clocks" file → clocks property missing
# If no "clock-names" file → clock-names missing

dmesg | grep KOTESH_CLK
# error=-2 = ENOENT = clock not found in DTS
```

### Fix
```bash
# In qemu-virt.dts, add both clock properties:
kotesh-clk@20002000 {
    compatible = "kotesh,clk-driver";
    reg = <0x0 0x20002000 0x0 0x1000>;
    clocks = <0x8000>;           # phandle to apb-pclk
    clock-names = "apb_pclk";   # must match devm_clk_get() string
    status = "okay";
};
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 07 — Missing Regulator Property

### Symptom
```
KOTESH_VCC: probe called
KOTESH_VCC: failed to get regulator, error=-19
```

### What to check
```bash
ls /proc/device-tree/kotesh-vcc@20003000/
# If no "vcc-supply" file → regulator property missing

dmesg | grep KOTESH_VCC
# error=-19 = ENODEV = regulator device not found
```

### Fix
```bash
# In qemu-virt.dts:
kotesh-vcc@20003000 {
    compatible = "kotesh,regulator-driver";
    reg = <0x0 0x20003000 0x0 0x1000>;
    vcc-supply = <0x8000>;   # phandle to fixed regulator
    status = "okay";
};
dtc -I dts -O dtb -o $DTB $DTS
```

---

## DTS Issue 08 — Missing of_match_table

### Symptom
```
# Completely silent — no dmesg output at all
# Device exists, driver exists, but never bound
```

### What to check
```bash
ls /sys/bus/platform/drivers/kotesh_of/
# No device symlink = driver never bound to device

cat /sys/bus/platform/devices/20004000.kotesh-of/uevent
# No DRIVER= line = unbound

# Check driver source — is of_match_table present?
grep "of_match_table" $PANIC_DIR/files/kotesh_of_driver.c
```

### Fix
```bash
# In driver .c file, add of_match_table to platform_driver struct:
static struct platform_driver kotesh_of_driver = {
    .probe = kotesh_of_probe,
    .driver = {
        .name = "kotesh_of",
        .of_match_table = of_match_ptr(kotesh_of_ids),  # ADD THIS
    },
};
# Rebuild: bitbake kotesh-of-driver -c cleansstate && bitbake core-image-minimal
```

---

## DTS Issue 09 — Driver Not Included in Image

### Symptom
```
Device tree node exists but driver never loads
No module in /lib/modules/
```

### What to check
```bash
find /lib/modules -name "kotesh_of*"
# No output = .ko not in rootfs

ls /sys/bus/platform/drivers/ | grep kotesh_of
# No output = driver never registered
```

### Fix
```bash
# In ~/yocto/poky/meta-kotesh/recipes-core/images/core-image-minimal.bbappend:
IMAGE_INSTALL += "kotesh-of-driver"

# Rebuild:
MACHINE=qemuarm64 bitbake core-image-minimal
```

---

## DTS Issue 10 — Duplicate Compatible String

### Symptom
```
KOTESH_MULTI_A: probe called — I am driver A
# Driver B never appears in dmesg
# Both modules loaded but only A bound
```

### What to check
```bash
cat /sys/bus/platform/devices/20005000.kotesh-multi/uevent | grep DRIVER
# DRIVER=kotesh_multi_a  ← only A bound, B silently ignored

lsmod | grep kotesh_multi
# Both loaded but B has no device
```

### Why it happens
```
Two drivers with same compatible string
Kernel binds first registered driver
Second driver loads but finds no unbound device
```

### Fix
```bash
# Give unique compatible strings:
# Driver A: compatible = "kotesh,multi-driver-v1"
# Driver B: compatible = "kotesh,multi-driver-v2"
# DTS node: compatible = "kotesh,multi-driver-v1";
```

---

## DTS Issue 11 — Wrong interrupt-cells Format

### Symptom
```
Probe deferred forever
interrupt-parent phandle not resolved
```

### What to check
```bash
# Check interrupt controller #interrupt-cells:
cat /proc/device-tree/intc@8000000/#interrupt-cells
# If = 3 → need: interrupts = <type number trigger>
# If = 1 → need: interrupts = <number>

# AM335x uses 1 cell: interrupts = <72>
# QEMU GIC uses 3 cells: interrupts = <0x0 0x0a 0x4>
```

### Fix
```bash
# Match format to controller:
# GIC (QEMU virt):    interrupts = <0x0 0x0a 0x4>;
# AM335x INTC:        interrupts = <72>;
```

---

## DTS Issue 12 — Platform Driver Probe Cycle

### Complete verification steps
```bash
# 1. Verify DTS node has correct compatible:
cat /proc/device-tree/my-bsp-device/compatible

# 2. Verify driver is loaded:
lsmod | grep my_bsp

# 3. Verify probe was called:
dmesg | grep "Probe Successful\|my-bsp"

# 4. Verify device is bound:
ls /sys/bus/platform/drivers/my_bsp_driver/
# Should show symlink to device
```

---

# CATEGORY 3 — KERNEL PANIC ISSUES (01–10)
# These issues = kernel crashes, oops, or silent corruption

---

## Panic Issue 01 — NULL Pointer Dereference

### Symptom
```
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
ESR = 0x0000000096000045
EC = 0x25: DABT (current EL)
WnR = 1  ← Write fault
x0 = 0x0 ← NULL pointer in register
Internal error: Oops: [#1] PREEMPT SMP
```

### What to check
```bash
dmesg | grep -i "null\|oops\|unable to handle"

# Key fields to read:
# EC = 0x25 → Data Abort (memory access fault)
# WnR = 1   → Write fault (wrote to bad address)
# WnR = 0   → Read fault (read from bad address)
# x0 = 0x0  → register was NULL
# pc : function+offset → exact line of crash
```

### Fix pattern
```c
// Wrong:
int *ptr = NULL;
*ptr = 42;          // crash

// Correct:
int *ptr = kmalloc(sizeof(int), GFP_KERNEL);
if (!ptr)           // always check NULL after alloc
    return -ENOMEM;
*ptr = 42;
```

---

## Panic Issue 02 — Stack Overflow

### Symptom
```
Insufficient stack space to handle exception!
Task stack:     [0xffffffc009798000..0xffffffc00979c000]
Overflow stack: [0xffffff803fdc42c0..0xffffff803fdc52c0]
Kernel panic - not syncing: kernel stack overflow
# ALWAYS FATAL — system freezes
```

### What to check
```bash
dmesg | grep -i "stack\|overflow\|insufficient"

# Look for infinite recursion in call trace:
# lr : infinite_recurse+0x3c → same function repeating
```

### Fix pattern
```c
// Wrong — infinite recursion:
void recurse(int n) {
    recurse(n + 1);   // never stops
}

// Correct — always have base case:
void recurse(int n) {
    if (n > 100) return;   // base case
    recurse(n + 1);
}
```

---

## Panic Issue 03 — BUG_ON / WARN_ON

### Symptom WARN_ON (non-fatal)
```
------------[ cut here ]------------
WARNING: CPU: 0 PID: 114 at drivers/kotesh_bugon.c:13
Tainted: G W O   ← W = Warning taint
---[ end trace ]---
# System CONTINUES running
```

### Symptom BUG_ON (fatal)
```
------------[ cut here ]------------
kernel BUG at drivers/kotesh_bugon.c:15!
Internal error: Oops - BUG: [#1]
Kernel panic - not syncing: Fatal exception
# System STOPS
```

### What to check
```bash
dmesg | grep -i "cut here\|warning\|bug\|taint"

# Taint flags:
# G = proprietary module
# W = WARN_ON triggered
# O = out-of-tree module
```

### Key difference
```
WARN_ON(condition) → prints warning, continues  → use for recoverable issues
BUG_ON(condition)  → kills kernel, stops system → use for impossible states
```

---

## Panic Issue 04 — Divide by Zero

### Symptom (ARM64)
```
Unexpected kernel BRK exception at EL1
BRK handler: 00000000f20003e8
Kernel panic - not syncing: BRK handler: unexpected BRK exception in kernel
```

### ARM64 vs x86 CRITICAL difference
```
x86:   "divide error: 0000"          ← hardware trap
ARM64: "Unexpected kernel BRK exception" ← compiler inserted BRK #0x3e80

ARM64 has NO hardware divide-by-zero trap.
GCC inserts BRK instruction before division.
If divisor=0 at runtime → BRK fires → panic.
```

### What to check
```bash
dmesg | grep -i "BRK\|divide\|unexpected"

# f20003e8 in BRK handler = divide by zero opcode
```

### Fix pattern
```c
// Wrong:
result = a / b;   // b could be 0

// Correct:
if (b == 0) {
    dev_err(&pdev->dev, "divisor is zero\n");
    return -EINVAL;
}
result = a / b;
```

---

## Panic Issue 05 — Hung Task

### Symptom
```
INFO: task udevd:116 blocked for more than 30 seconds.
Call trace:
 msleep+0x40/0x60
 kotesh_hungtask_probe+0x2c/0x40
# NOT fatal — system survives, worker killed
```

### What to check
```bash
dmesg | grep -i "hung\|blocked\|taking a long time"

# Reduce timeout for faster testing:
echo 30 > /proc/sys/kernel/hung_task_timeout_secs

# Check if task is sleeping or spinning:
cat /proc/<pid>/wchan
# D state = uninterruptible sleep (blocking call)
# R state = running (spinlock or busy loop)
```

### Fix pattern
```c
// Wrong — blocking forever in probe:
while (1) {
    msleep(1000);   // blocks udevd worker forever
}

// Correct — use workqueue for long operations:
static void my_work_handler(struct work_struct *work) {
    // long running work here — separate thread context
}
DECLARE_WORK(my_work, my_work_handler);
schedule_work(&my_work);   // in probe — returns immediately
```

---

## Panic Issue 06 — Oops vs panic_on_oops

### Part A — Default: Oops survives (el0 context)
```bash
# After boot:
dmesg | grep -i "oops\|unable to handle"
cat /proc/uptime   # system still running!

# el0t_64_sync_handler in call trace = userspace context = survivable
```

### Part B — Enable panic_on_oops
```bash
echo 1 > /proc/sys/kernel/panic_on_oops
echo c > /proc/sysrq-trigger   # trigger crash
# → Kernel panic - not syncing: sysrq triggered crash
# → QEMU FREEZES
```

### Key rule
```
el0t_64_sync_handler in call trace → userspace context → Oops survives
el1h_64_sync_handler in call trace → kernel context   → always fatal

panic_on_oops=1 → converts ALL Oops to panic regardless of context
```

---

## Panic Issue 07 — Use After Free (UAF)

### Symptom — COMPLETELY SILENT
```
KOTESH_UAF: allocated data at ffffff8002e98c00, value=42
KOTESH_UAF: freed data
KOTESH_UAF: accessing freed memory...
KOTESH_UAF: data->value = 0    ← was 42, SLUB overwrote it!
KOTESH_UAF: wrote to freed memory — value now 99
# NO CRASH. NO WARNING. System runs normally.
```

### What to check
```bash
# UAF is invisible without KASAN:
zcat /proc/config.gz | grep CONFIG_KASAN
# (not set) = UAF is silent

# With SLUB poison (partial detection):
# Add to QEMU -append: slub_debug=P
# UAF read returns 0x6b6b6b6b instead of real data

# With KASAN enabled:
dmesg | grep -i "kasan\|use-after-free"
```

### Fix pattern
```c
// Wrong:
kfree(data);
data->value = 99;   // UAF!

// Correct — always NULL after free:
kfree(data);
data = NULL;        // any subsequent access → visible NULL Oops

// Best — use devm_ (automatic cleanup):
data = devm_kmalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
// No kfree needed — kernel cleans up on device remove
```

---

## Panic Issue 08 — Double Free

### Symptom
```
KOTESH_DFREE: about to double free...
general protection fault
x4 : dead000000000100   ← SLUB poison value — freed memory marker
Kernel panic - not syncing: Oops - General protection fault
```

### What to check
```bash
dmesg | grep -i "double free\|dead0000\|general protection"

# dead000000000100 and dead000000000200 are SLUB poison values
# Seeing these in registers = double free or use-after-free detected by SLUB
```

### Fix pattern
```c
// Wrong:
kfree(data);
kfree(data);   // double free!

// Correct:
kfree(data);
data = NULL;   // NULL prevents double free
kfree(data);   // kfree(NULL) is safe — does nothing
```

---

## Panic Issue 09 — OOM (Out of Memory)

### Symptom
```
KOTESH_OOM: allocated 900 MB so far...
page allocation failure: order:8, mode:0x40cc0(GFP_KERNEL|__GFP_COMP)
KOTESH_OOM: kmalloc failed at iteration 945
# NOT fatal — kmalloc returns NULL, probe returns error
```

### What to check
```bash
dmesg | grep -i "page allocation failure\|oom\|out of memory"

# Check memory state:
cat /proc/meminfo | grep -E "MemFree|Slab|SUnreclaim"
free -m

# Smoking gun:
# Slab: very high = memory leak in driver
# SUnreclaim: high = unreclaimable kernel allocations
```

### Fix pattern
```c
// Wrong — never freeing allocations:
for (i = 0; i < 1000; i++) {
    buf = kmalloc(1024 * 1024, GFP_KERNEL);
    // never kfree(buf) = memory leak
}

// Correct — always free or use devm_:
buf = devm_kmalloc(&pdev->dev, size, GFP_KERNEL);
// freed automatically when device removed
```

---

## Panic Issue 10 — Unaligned Access / Bad Pointer

### Symptom Part 1 — Unaligned (ARM64 survives silently)
```
KOTESH_UNALIGNED: read value 16777216
# Expected 16909060 — got wrong data — SILENT CORRUPTION
# ARM64 SCTLR_EL1.A=0 → hardware fixup → no crash but wrong data
```

### Symptom Part 2 — Bad pointer (Oops)
```
Unable to handle kernel paging request at virtual address deadbeef00000000
ESR = 0x0000000096000004
FSC = 0x04: level 0 translation fault   ← no page table entry
```

### What to check
```bash
dmesg | grep -i "paging request\|translation fault\|unaligned"

# FSC values:
# 0x04 = level 0 fault → completely unmapped address (bad pointer)
# 0x05 = level 1 fault → NULL pointer dereference
# 0x07 = level 3 fault → page not present

# Check ARM64 alignment handling:
cat /proc/cpu/alignment 2>/dev/null || echo "not available on ARM64"
```

### Fix pattern
```c
// Wrong — unaligned u32 access:
u8 buf[8];
u32 *ptr = (u32 *)(buf + 1);   // offset 1 = not 4-byte aligned
val = *ptr;                     // silent wrong data on ARM64

// Correct — use get_unaligned:
#include <linux/unaligned.h>
val = get_unaligned_le32(buf + 1);   // safe unaligned read
```

---

# COMPLETE DIAGNOSTIC CHEAT SHEET

## Boot Issues — First Command
| # | Issue | First Command | Key Symptom |
|---|---|---|---|
| 01 | No console | Check -append console= | Blank screen |
| 02 | Wrong root device | Check -append root= | VFS panic |
| 03 | Ext4 as module | `zcat /proc/config.gz | grep EXT4` | Mount fail |
| 04 | Missing block driver | `zcat /proc/config.gz | grep VIRTIO_BLK` | No virtio |
| 05 | No init | `ls /sbin/init` | Init panic |

## DTS Issues — First Command
| # | Issue | First Command | Key Symptom |
|---|---|---|---|
| 01 | Compatible mismatch | `cat /proc/device-tree/<node>/compatible` | No probe |
| 02 | Node disabled | `cat /proc/device-tree/<node>/status` | No probe |
| 03 | Missing reg | `ls /proc/device-tree/<node>/` | error=-22 |
| 04 | Wrong IRQ | `cat /proc/interrupts` | No probe |
| 05 | Probe deferral | `cat /sys/kernel/debug/devices_deferred` | No probe |
| 06 | Missing clock | `ls /proc/device-tree/<node>/` | error=-2 |
| 07 | Missing regulator | `ls /proc/device-tree/<node>/` | error=-19 |
| 08 | No of_match_table | `ls /sys/bus/platform/drivers/<drv>/` | Unbound |
| 09 | Driver not in image | `find /lib/modules -name "*.ko"` | No .ko |
| 10 | Duplicate compatible | `cat /sys/.../uevent | grep DRIVER` | Only one bound |

## Panic Issues — First Command
| # | Issue | First Command | Fatal? |
|---|---|---|---|
| 01 | NULL pointer | `dmesg | grep "unable to handle"` | Oops |
| 02 | Stack overflow | `dmesg | grep "stack overflow"` | ✅ Always |
| 03 | BUG_ON/WARN_ON | `dmesg | grep "cut here"` | BUG=✅ WARN=❌ |
| 04 | Divide by zero | `dmesg | grep "BRK exception"` | ✅ Yes |
| 05 | Hung task | `dmesg | grep "blocked for more"` | ❌ Warning |
| 06 | Oops vs panic | `cat /proc/sys/kernel/panic_on_oops` | Configurable |
| 07 | Use after free | `zcat /proc/config.gz | grep KASAN` | ❌ Silent |
| 08 | Double free | `dmesg | grep "dead0000"` | ✅ Cascade |
| 09 | OOM | `dmesg | grep "page allocation failure"` | ❌ Soft |
| 10 | Unaligned/bad ptr | `dmesg | grep "paging request"` | Oops |

---

# DAILY PRACTICE METHOD

## Break → Diagnose → Fix cycle (do this for each issue)

```
Step 1 — BREAK IT
  Open ~/dtstest/qemu-virt.dts
  Make one change (remove a property, wrong value, disable node)
  Rebuild: dtc -I dts -O dtb -o $DTB $DTS
  Boot QEMU: ~/BSP-Lab/boot_qemu.sh

Step 2 — DIAGNOSE IT (without looking at docs)
  dmesg | grep -i "error\|fail\|warn\|kotesh"
  Read the error code
  Check /proc/device-tree/<node>/
  Check /sys/bus/platform/

Step 3 — FIX IT
  Identify the missing or wrong property
  Fix in DTS or driver
  Rebuild and boot
  Verify fix in dmesg

Step 4 — DOCUMENT IT
  Write what you broke, what you saw, what you fixed
  One .md file per issue
```

## Interview Answer Template

When interviewer asks "how do you debug a driver that doesn't probe?":

```
1. First I check dmesg for error codes
   error=-2  → missing DTS property
   error=-19 → missing device/regulator
   error=-22 → wrong DTS value

2. Then I check /proc/device-tree/<node>/
   See which properties are present or missing

3. Then I check /sys/kernel/debug/devices_deferred
   If device listed → probe deferred → dependency missing

4. Then I check /sys/bus/platform/drivers/<driver>/
   If no device symlink → compatible mismatch or no of_match_table

5. Fix in DTS, rebuild DTB, reboot, verify in dmesg
```

---

*Kotesh S — BSP Lab Reference — March 2026*
*github.com/kotesh508/linux-bsp-debugging-kb*

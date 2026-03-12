# BSP-Lab 03 — Kernel Panic Issues 06–10: Individual Reproduce Commands
# Real driver code | Exact build steps | Actual observed output

---

## Common Setup
```bash
EXPORT PANIC_DIR=~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver
EXPORT DTS=~/dtstest/qemu-virt.dts
EXPORT DTB=~/dtstest/kotesh-test.dtb

#Varify with confomation 
echo $DTB 
echo $DTS
ls $DTS

# After every DTS change:
dtc -I dts -O dtb -o $DTB $DTS

# After every driver/recipe change:
cd ~/yocto/poky && source oe-init-build-env build
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal

# Boot command:
qemu-system-aarch64 \
  -machine virt -cpu cortex-a57 -m 1024 -nographic \
  -kernel /home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/Image \
  -dtb /home/kotesh/dtstest/kotesh-test.dtb \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive if=none,format=raw,file=/home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4,id=hd0 \
  -device virtio-blk-device,drive=hd0
```

---

## Panic 06 — Kernel Oops vs Panic (panic_on_oops)

### Reuses Panic 01 (NULL pointer) driver — no new driver needed

### Part A: Default boot — Oops, system survives

#### Step 1: Use kotesh_null_ptr driver from Panic 01
```bash
# kotesh_null_ptr.c already exists from Panic 01
# DTS: kotesh-null { compatible = "kotesh,null-ptr"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU — login as root
```

#### Step 2: Verify Oops — system survives
```bash
dmesg | grep -i "oops\|null\|KOTESH_NULL"
# Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
# udevd[110]: worker [N] ... terminated

cat /proc/uptime
# 45.23 ...   ← still running!

echo "system survived the Oops!"
# system survived the Oops!
```

#### Expected Part A output
```
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
pc : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
lr : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]

# Key: exception at el0t_64_sync (userspace syscall context)
# el0 context = survivable Oops — only udevd worker dies
# System reaches login prompt normally!

qemuarm64 login: root     ← SYSTEM ALIVE
```

---

### Part B: Enable panic_on_oops — Oops becomes hard panic

#### Step 1: Boot QEMU (same as Part A)
```bash
# Login as root after boot
```

#### Step 2: Enable panic_on_oops
```bash
echo 1 > /proc/sys/kernel/panic_on_oops
cat /proc/sys/kernel/panic_on_oops
# 1
```

#### Step 3: Trigger crash from KERNEL context using sysrq
```bash
echo c > /proc/sysrq-trigger
# This triggers BUG() from kernel context → guaranteed panic
```

#### Expected Part B output
```
sysrq: Trigger a crash
Kernel panic - not syncing: sysrq triggered crash
CPU: 0 PID: 337 Comm: sh Tainted: G W O 5.15.194-yocto-standard #1
Hardware name: linux,dummy-virt (DT)
Call trace:
 dump_backtrace+0x0/0x1a0
 show_stack+0x20/0x30
 dump_stack_lvl+0x7c/0xa0
 panic+0x17c/0x37c
 sysrq_handle_crash+0x28/0x38
 ...
Kernel Offset: disabled
---[ end Kernel panic - not syncing: sysrq triggered crash ]---
# QEMU FREEZES — no more output, no login prompt
```

### Key difference — el0 vs el1 context
```
Oops from el0t_64_sync (udevd loading module = userspace syscall):
  → exception in userspace context
  → only calling process (udevd worker) dies
  → SURVIVABLE even without panic_on_oops

Oops from el1 (sysrq or driver interrupt handler):
  → exception in kernel context
  → ALWAYS fatal, system halts
  → panic_on_oops=1 converts all el0 Oops to panic too

Check context in dmesg:
  el0t_64_sync_handler → userspace → survivable
  el1h_64_sync_handler → kernel   → always fatal
```

---

## Panic 07 — Use After Free (UAF)

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_uaf.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

struct kotesh_data {
    int value;
};

static int kotesh_uaf_probe(struct platform_device *pdev)
{
    struct kotesh_data *data;

    pr_info("KOTESH_UAF: probe called\n");

    data = kmalloc(sizeof(*data), GFP_KERNEL);
    if (!data)
        return -ENOMEM;

    data->value = 42;
    pr_info("KOTESH_UAF: allocated data at %px, value=%d\n", data, data->value);

    kfree(data);
    pr_info("KOTESH_UAF: freed data\n");

    /* USE AFTER FREE */
    pr_info("KOTESH_UAF: accessing freed memory...\n");
    pr_info("KOTESH_UAF: data->value = %d\n", data->value);   /* UAF read */
    data->value = 99;                                           /* UAF write */
    pr_info("KOTESH_UAF: wrote to freed memory — value now %d\n", data->value);

    return 0;
}

static const struct of_device_id kotesh_uaf_ids[] = {
    { .compatible = "kotesh,uaf-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_uaf_ids);

static struct platform_driver kotesh_uaf_driver = {
    .probe = kotesh_uaf_probe,
    .driver = { .name = "kotesh_uaf", .of_match_table = of_match_ptr(kotesh_uaf_ids) },
};
module_platform_driver(kotesh_uaf_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_uaf.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_uaf"
# DTS: kotesh-uaf { compatible = "kotesh,uaf-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU — login as root
```

### Step 6: Check output
```bash
dmesg | grep KOTESH_UAF
cat /proc/uptime
echo "survived?"
```

### Expected output — completely silent corruption
```
[    5.304793] KOTESH_UAF: probe called
[    5.305203] KOTESH_UAF: allocated data at ffffff8002e98c00, value=42
[    5.305751] KOTESH_UAF: freed data
[    5.318735] KOTESH_UAF: accessing freed memory...
[    5.319205] KOTESH_UAF: data->value = 0        ← was 42, SLUB overwrote it!
[    5.319515] KOTESH_UAF: wrote to freed memory — value now 99   ← silent write!

qemuarm64 login: root     ← SYSTEM SURVIVED — no crash, no warning!
```

### Why value changed 42 → 0
```
After kfree(data):
  SLUB allocator reclaimed the memory
  SLUB wrote its freelist metadata into first bytes
  data->value field (at offset 0) = overwritten with 0x0 (SLUB next pointer)
  We read 0 instead of 42 — SILENT DATA CORRUPTION

With KASAN enabled (not in this kernel):
  BUG: KASAN: use-after-free in kotesh_uaf_probe+0x.../0x...
  Read of size 4 at addr ffffff8002e98c00 by task udevd/114
```

### Runtime diagnostics (run after boot)
```bash
# Check if KASAN is available
zcat /proc/config.gz | grep KASAN
# (not set in our kernel — that's why UAF is silent)

# Enable SLUB poison to detect UAF at runtime:
# Add slub_debug=P to kernel cmdline

# Check SLUB stats:
cat /proc/slabinfo | head -5
```

---

## Panic 08 — Double Free

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_doublefree.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

struct kotesh_data {
    int value;
};

static int kotesh_doublefree_probe(struct platform_device *pdev)
{
    struct kotesh_data *data;

    pr_info("KOTESH_DFREE: probe called\n");

    data = kmalloc(sizeof(*data), GFP_KERNEL);
    if (!data)
        return -ENOMEM;

    data->value = 42;
    pr_info("KOTESH_DFREE: allocated at %px\n", data);

    kfree(data);
    pr_info("KOTESH_DFREE: first kfree — OK\n");

    pr_info("KOTESH_DFREE: about to double free...\n");
    kfree(data);   /* DOUBLE FREE */
    pr_info("KOTESH_DFREE: after double free (should not reach)\n");

    return 0;
}

static const struct of_device_id kotesh_doublefree_ids[] = {
    { .compatible = "kotesh,doublefree-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_doublefree_ids);

static struct platform_driver kotesh_doublefree_driver = {
    .probe = kotesh_doublefree_probe,
    .driver = { .name = "kotesh_dfree", .of_match_table = of_match_ptr(kotesh_doublefree_ids) },
};
module_platform_driver(kotesh_doublefree_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_doublefree.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_doublefree"
# DTS: kotesh-dfree { compatible = "kotesh,doublefree-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU — watch for cascade
```

### Expected output — cascade Oops
```
[    5.xxx] KOTESH_DFREE: probe called
[    5.xxx] KOTESH_DFREE: allocated at ffffff8002e98c00
[    5.xxx] KOTESH_DFREE: first kfree — OK
[    5.xxx] KOTESH_DFREE: about to double free...

[    6.xxx] Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
[    6.xxx] x4 : dead000000000100   ← SLUB LIST_POISON2 — SMOKING GUN!
[    6.xxx] pc : get_page_from_freelist+0x...   ← crash in page allocator (unrelated!)

[    6.xxx] Internal error: Oops: 0000000096000045 [#2] PREEMPT SMP
...
[    9.038] Internal error: Oops: 0000000096000045 [#9] PREEMPT SMP
[    9.056] WARNING: CPU: 0 PID: 81 at kernel/exit.c:788
[    9.xxx] Fixing recursive fault but reboot is needed!

# QEMU eventually halts after cascade
```

### Key diagnostic fields
```
x4 : dead000000000100   ← THIS IS THE SMOKING GUN
                           SLUB LIST_POISON2 magic value
                           Means: kernel is reading a freelist pointer
                           that was poisoned after kfree()
                           = you are accessing already-freed memory

[#1] → [#9]             ← Escalating Oops counter
                           Each Oops corrupts more kernel state
                           [#5]+ = severe heap corruption
                           "Fixing recursive fault but reboot is needed!" = game over

Crash at get_page_from_freelist  ← UNRELATED to actual bug site
                                   This is hallmark of heap corruption:
                                   crash happens far from the real bug
```

### Other SLUB poison values
```
dead000000000100 = LIST_POISON2 (freelist next pointer — double free)
dead000000000200 = LIST_POISON1 (freelist prev pointer)
6b6b6b6b6b6b6b6b = POISON_FREE (freed memory marker)
5a5a5a5a5a5a5a5a = POISON_END  (end of allocation marker)
```

---

## Panic 09 — Out of Memory (OOM)

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_oom.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>

static int kotesh_oom_probe(struct platform_device *pdev)
{
    void **ptrs;
    int i, count = 0;
    size_t chunk = 1024 * 1024;  /* 1MB per allocation */

    pr_info("KOTESH_OOM: probe called\n");
    pr_info("KOTESH_OOM: starting memory exhaustion — allocating 1MB chunks...\n");

    ptrs = kmalloc(sizeof(void *) * 2048, GFP_KERNEL);
    if (!ptrs)
        return -ENOMEM;

    for (i = 0; i < 2048; i++) {
        ptrs[i] = kmalloc(chunk, GFP_KERNEL);
        if (!ptrs[i]) {
            pr_info("KOTESH_OOM: kmalloc failed at iteration %d (%d MB allocated)\n",
                    i, count);
            break;
        }
        memset(ptrs[i], 0xAB, chunk);
        count++;
        if (count % 100 == 0)
            pr_info("KOTESH_OOM: allocated %d MB so far...\n", count);
    }

    pr_info("KOTESH_OOM: allocated total %d MB — OOM should fire!\n", count);
    return 0;
}

static const struct of_device_id kotesh_oom_ids[] = {
    { .compatible = "kotesh,oom-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_oom_ids);

static struct platform_driver kotesh_oom_driver = {
    .probe = kotesh_oom_probe,
    .driver = { .name = "kotesh_oom", .of_match_table = of_match_ptr(kotesh_oom_ids) },
};
module_platform_driver(kotesh_oom_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_oom.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_oom"
# DTS: kotesh-oom { compatible = "kotesh,oom-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU — login as root
```

### Step 6: Check memory state after boot
```bash
dmesg | grep -i "oom\|killed\|page allocation failure\|KOTESH_OOM"
cat /proc/meminfo | grep -E "MemTotal|MemFree|Slab|SUnreclaim"
free -m
```

### Expected output
```
[    4.950909] KOTESH_OOM: probe called
[    4.951198] KOTESH_OOM: starting memory exhaustion — allocating 1MB chunks...
[    5.255074] KOTESH_OOM: allocated 100 MB so far...
[    5.492508] KOTESH_OOM: allocated 200 MB so far...
[    5.706127] KOTESH_OOM: allocated 300 MB so far...
[    5.798259] KOTESH_OOM: allocated 400 MB so far...
[    5.854500] KOTESH_OOM: allocated 500 MB so far...
[    5.914308] KOTESH_OOM: allocated 600 MB so far...
[    5.970952] KOTESH_OOM: allocated 700 MB so far...
[    6.028644] KOTESH_OOM: allocated 800 MB so far...
[    6.089846] KOTESH_OOM: allocated 900 MB so far...

[    6.142268] udevd: page allocation failure: order:8, mode:0x40cc0(GFP_KERNEL|__GFP_COMP)
               nodemask=(null),cpuset=/,mems_allowed=0
[    6.147519]  kotesh_oom_probe+0x68/0xf4 [kotesh_oom]

[    6.192237] KOTESH_OOM: kmalloc failed at iteration 945 (945 MB allocated)
[    6.192700] KOTESH_OOM: allocated total 945 MB — OOM should fire!
```

### /proc/meminfo after boot
```
MemTotal:    1009136 kB   ← 985 MB total
MemFree:        6728 kB   ← only 6 MB free!
Slab:         987940 kB   ← 964 MB in slab allocator (our allocations!)
SUnreclaim:   978300 kB   ← 955 MB unreclaimable
```

### free -m after boot
```
               total  used  free  shared  buff/cache  available
Mem:             985   963     6       0          15          8
Swap:              0     0     0
```

### Key diagnostic fields
```
"page allocation failure: order:8"  ← tried to alloc 2^8=256 contiguous pages (1MB)
                                       failed due to memory fragmentation
"mode:0x40cc0(GFP_KERNEL|__GFP_COMP)" ← normal kernel alloc, compound page
Slab: 987940 kB                     ← smoking gun: nearly all RAM in slab
SUnreclaim: 978300 kB               ← unreclaimable = our kmalloc chunks
"kmalloc failed at iteration 945"   ← 945 MB allocated before failure
System survived because probe() returned — pressure released
```

---

## Panic 10 — Bad Pointer / Unaligned Access

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_unaligned.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

static int kotesh_unaligned_probe(struct platform_device *pdev)
{
    u8 buf[8] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07};
    u32 *ptr;
    u32 val;

    pr_info("KOTESH_UNALIGNED: probe called\n");
    pr_info("KOTESH_UNALIGNED: forcing unaligned memory access\n");

    /* Unaligned: u32 ptr at offset+1 (not 4-byte aligned) */
    ptr = (u32 *)(buf + 1);
    pr_info("KOTESH_UNALIGNED: address = %px\n", ptr);
    val = *ptr;
    pr_info("KOTESH_UNALIGNED: read value %u (0x%08x)\n", val, val);
    pr_info("KOTESH_UNALIGNED: expected 0x01020304 = 16909060\n");

    /* Bad pointer — will crash */
    pr_info("KOTESH_UNALIGNED: now trying bad pointer access...\n");
    ptr = (u32 *)0xdeadbeef00000000UL;
    pr_info("KOTESH_UNALIGNED: about to dereference bad pointer...\n");
    val = *ptr;
    pr_info("KOTESH_UNALIGNED: val=%u (should not reach)\n", val);

    return 0;
}

static const struct of_device_id kotesh_unaligned_ids[] = {
    { .compatible = "kotesh,unaligned-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_unaligned_ids);

static struct platform_driver kotesh_unaligned_driver = {
    .probe = kotesh_unaligned_probe,
    .driver = { .name = "kotesh_unaligned", .of_match_table = of_match_ptr(kotesh_unaligned_ids) },
};
module_platform_driver(kotesh_unaligned_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_unaligned.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_unaligned"
# DTS: kotesh-unaligned { compatible = "kotesh,unaligned-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU
```

### Expected output — Part 1: Unaligned (ARM64 survives)
```
[    8.453489] KOTESH_UNALIGNED: probe called
[    8.454189] KOTESH_UNALIGNED: forcing unaligned memory access
[    8.479630] KOTESH_UNALIGNED: address = (____ptrval____)
[    8.480199] KOTESH_UNALIGNED: read value 16777216   ← ARM64 HW fixup, no crash!
               (expected 16909060 = 0x01020304, got 16777216 = 0x01000000 — wrong data!)
```

### Expected output — Part 2: Bad pointer (Oops)
```
[    8.480400] KOTESH_UNALIGNED: now trying bad pointer access...
[    8.480600] KOTESH_UNALIGNED: about to dereference bad pointer...

Unable to handle kernel paging request at virtual address deadbeef00000000
Mem abort info:
  ESR = 0x0000000096000004
  EC = 0x25: DABT (current EL)
  FSC = 0x04: level 0 translation fault
pc : kotesh_unaligned_probe+0xXX/0xXX [kotesh_unaligned]
Internal error: Oops: 0000000096000004 [#1] PREEMPT SMP
```

### Key diagnostic fields
```
Unaligned access on ARM64:
  SCTLR_EL1.A = 0 (Linux default) → HW fixup, no fault
  Value 16777216 ≠ 16909060 → SILENT DATA CORRUPTION
  Performance penalty: multiple bus transactions

Bad pointer (0xdeadbeef00000000):
  "kernel paging request at virtual address deadbeef00000000"
  FSC = 0x04: level 0 translation fault → no page table entry at all
  Different from NULL (level 1 fault) — both are DABT EC=0x25
```

### After boot checks
```bash
# Check ARM64 alignment state
cat /proc/cpu/alignment
# 0: no fixups counted (if CONFIG_ARM64_SW_TTBR0_PAN enabled)
# OR file not present

# Check unaligned access stats:
cat /proc/cpu/alignment 2>/dev/null || echo "not available"
```

---

## Master Build Script — Run Any Single Issue

```bash
#!/bin/bash
# Usage: ./run_panic.sh <issue_number>
# Example: ./run_panic.sh 7

ISSUE=$1
PANIC_DIR=~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver
DTS=~/dtstest/qemu-virt.dts
DTB=~/dtstest/kotesh-test.dtb

# Map issue number to compatible string
declare -A COMPAT=(
    [1]="kotesh,null-ptr"
    [2]="kotesh,stack-overflow"
    [3]="kotesh,bugon-driver"
    [4]="kotesh,divzero-driver"
    [5]="kotesh,hungtask-driver"
    [7]="kotesh,uaf-driver"
    [8]="kotesh,doublefree-driver"
    [9]="kotesh,oom-driver"
    [10]="kotesh,unaligned-driver"
)

declare -A MODULE=(
    [1]="kotesh_null_ptr"
    [2]="kotesh_stack_overflow"
    [3]="kotesh_bugon"
    [4]="kotesh_divzero"
    [5]="kotesh_hungtask"
    [7]="kotesh_uaf"
    [8]="kotesh_doublefree"
    [9]="kotesh_oom"
    [10]="kotesh_unaligned"
)

echo "Setting up for Panic Issue $ISSUE: ${COMPAT[$ISSUE]}"

# All panic DTS nodes to disable
ALL_NODES=(
    "kotesh-null:kotesh,null-ptr"
    "kotesh-stack:kotesh,stack-overflow"
    "kotesh-bugon:kotesh,bugon-driver"
    "kotesh-divzero:kotesh,divzero-driver"
    "kotesh-hung:kotesh,hungtask-driver"
    "kotesh-uaf:kotesh,uaf-driver"
    "kotesh-dfree:kotesh,doublefree-driver"
    "kotesh-oom:kotesh,oom-driver"
    "kotesh-unaligned:kotesh,unaligned-driver"
)

echo "Update $DTS manually:"
echo "  1. Set node with compatible=${COMPAT[$ISSUE]} to: status = \"okay\";"
echo "  2. Set ALL other panic nodes to: status = \"disabled\";"
echo "  3. Run: dtc -I dts -O dtb -o $DTB $DTS"
echo ""
echo "Update $PANIC_DIR/kotesh-panic-driver.bb:"
echo "  SRC_URI = \"file://${MODULE[$ISSUE]}.c file://Makefile\""
echo "  KERNEL_MODULE_AUTOLOAD += \"${MODULE[$ISSUE]}\""
echo ""
echo "Then build:"
echo "  cd ~/yocto/poky && source oe-init-build-env build"
echo "  MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate"
echo "  MACHINE=qemuarm64 bitbake core-image-minimal"
```

---

## Complete Panic Summary — All 10

| # | DTS compatible | Driver file | Fatal? | Key Signature |
|---|---|---|---|---|
| 01 | `kotesh,null-ptr` | `kotesh_null_ptr.c` | Oops (el0=survive) | `NULL pointer dereference at 0x0` |
| 02 | `kotesh,stack-overflow` | `kotesh_stack_overflow.c` | ✅ Always | `kernel stack overflow` |
| 03 | `kotesh,bugon-driver` | `kotesh_bugon.c` | ❌/✅ WARN/BUG | `cut here` + `WARNING` or `BUG` |
| 04 | `kotesh,divzero-driver` | `kotesh_divzero.c` | ✅ Yes | `Unexpected kernel BRK exception` |
| 05 | `kotesh,hungtask-driver` | `kotesh_hungtask.c` | ❌ Warning | `worker taking a long time` |
| 06 | reuse `kotesh,null-ptr` | reuse null_ptr | Configurable | `echo c > /proc/sysrq-trigger` |
| 07 | `kotesh,uaf-driver` | `kotesh_uaf.c` | ❌ Silent | value 42→0, no crash |
| 08 | `kotesh,doublefree-driver` | `kotesh_doublefree.c` | ✅ Cascade | `dead000000000100` in x4 |
| 09 | `kotesh,oom-driver` | `kotesh_oom.c` | ❌ Soft | `page allocation failure: order:8` |
| 10 | `kotesh,unaligned-driver` | `kotesh_unaligned.c` | Oops (bad ptr) | ARM64 HW fixup → silent |

## DTS Switch Template — Copy-Paste for Each Issue
```dts
/* Paste all of these into qemu-virt.dts before last }; */
/* Enable ONLY the issue you want, disable rest         */

kotesh-null      { compatible = "kotesh,null-ptr";          status = "disabled"; };
kotesh-stack     { compatible = "kotesh,stack-overflow";    status = "disabled"; };
kotesh-bugon     { compatible = "kotesh,bugon-driver";      status = "disabled"; };
kotesh-divzero   { compatible = "kotesh,divzero-driver";    status = "disabled"; };
kotesh-hung      { compatible = "kotesh,hungtask-driver";   status = "disabled"; };
kotesh-uaf       { compatible = "kotesh,uaf-driver";        status = "disabled"; };
kotesh-dfree     { compatible = "kotesh,doublefree-driver"; status = "disabled"; };
kotesh-oom       { compatible = "kotesh,oom-driver";        status = "disabled"; };
kotesh-unaligned { compatible = "kotesh,unaligned-driver";  status = "disabled"; };

/* Change ONE of the above to: status = "okay"; */
```

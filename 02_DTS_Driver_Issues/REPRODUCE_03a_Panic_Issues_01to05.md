# BSP-Lab 03 — Kernel Panic Issues 01–05: Individual Reproduce Commands
# Real driver code | Exact build steps | Actual observed output

---

## Common Setup (do once)

```bash
PANIC_DIR=~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver
DTS=~/dtstest/qemu-virt.dts
DTB=~/dtstest/kotesh-test.dtb

# After EVERY DTS change:
dtc -I dts -O dtb -o $DTB $DTS

# After EVERY driver/recipe change:
cd ~/yocto/poky && source oe-init-build-env build
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal

# Boot command (same every time):
qemu-system-aarch64 \
  -machine virt -cpu cortex-a57 -m 1024 -nographic \
  -kernel /home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/Image \
  -dtb /home/kotesh/dtstest/kotesh-test.dtb \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive if=none,format=raw,file=/home/kotesh/yocto/poky/build/tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4,id=hd0 \
  -device virtio-blk-device,drive=hd0
```

## ⚠️ CRITICAL RULE FOR ALL PANIC ISSUES
```bash
# In qemu-virt.dts, ONLY the current issue's DTS node = "okay"
# ALL other panic nodes MUST be "disabled"
# This prevents cascade panics from interfering with the test
```

---

## Panic 01 — NULL Pointer Dereference

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_null_ptr.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

static int kotesh_null_probe(struct platform_device *pdev)
{
    int *ptr = NULL;
    pr_info("KOTESH_NULL: probe called\n");
    pr_info("KOTESH_NULL: about to dereference NULL pointer...\n");
    *ptr = 42;   /* NULL dereference */
    return 0;
}

static const struct of_device_id kotesh_null_ids[] = {
    { .compatible = "kotesh,null-ptr" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_null_ids);

static struct platform_driver kotesh_null_driver = {
    .probe = kotesh_null_probe,
    .driver = { .name = "kotesh_null", .of_match_table = of_match_ptr(kotesh_null_ids) },
};
module_platform_driver(kotesh_null_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2: Create Makefile
```bash
cat > $PANIC_DIR/files/Makefile << 'EOF'
obj-m := kotesh_null_ptr.o
all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules
modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules_install
clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) clean
EOF
```

### Step 3: Create recipe
```bash
cat > $PANIC_DIR/kotesh-panic-driver.bb << 'EOF'
SUMMARY = "Kotesh panic demo"
LICENSE = "CLOSED"
inherit module
SRC_URI = "file://kotesh_null_ptr.c file://Makefile"
S = "${WORKDIR}"
KERNEL_MODULE_AUTOLOAD += "kotesh_null_ptr"
EOF
```

### Step 4: Enable DTS node
```bash
nano $DTS
# Add this node (disable all others):
# kotesh-null { compatible = "kotesh,null-ptr"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
cd ~/yocto/poky && source oe-init-build-env build
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU
```

### Expected output
```
[    x.x] KOTESH_NULL: probe called
[    x.x] KOTESH_NULL: about to dereference NULL pointer...

Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
Mem abort info:
  ESR = 0x0000000096000045
  EC = 0x25: DABT (current EL), IL = 32 bits
  SET = 0, FnV = 0
  EA = 0, S1PTW = 0
  FSC = 0x05: level 1 translation fault
Data abort info:
  ISV = 0, ISS = 0x00000045
  CM = 0, WnR = 1                ← WnR=1 means WRITE fault
x0 : 0000000000000000            ← x0 = NULL confirms it
pc : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
```

### Key diagnostic fields
```
EC = 0x25    → Data Abort (DABT) — memory access fault
WnR = 1      → Write fault (we wrote to NULL)
x0 = 0x0     → Register holding NULL pointer
[#1]         → First Oops (system may survive)
```

### After boot check (system survives Oops from el0 context):
```bash
dmesg | grep -i "null\|oops\|KOTESH_NULL"
cat /proc/uptime   # still running!
```

---

## Panic 02 — Stack Overflow

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_stack_overflow.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

static void infinite_recurse(int depth)
{
    pr_info("KOTESH_STACK: depth=%d\n", depth);
    infinite_recurse(depth + 1);
}

static int kotesh_stack_probe(struct platform_device *pdev)
{
    pr_info("KOTESH_STACK: probe called\n");
    pr_info("KOTESH_STACK: starting infinite recursion...\n");
    infinite_recurse(0);
    return 0;
}

static const struct of_device_id kotesh_stack_ids[] = {
    { .compatible = "kotesh,stack-overflow" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_stack_ids);

static struct platform_driver kotesh_stack_driver = {
    .probe = kotesh_stack_probe,
    .driver = { .name = "kotesh_stack", .of_match_table = of_match_ptr(kotesh_stack_ids) },
};
module_platform_driver(kotesh_stack_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2: Update Makefile
```bash
cat > $PANIC_DIR/files/Makefile << 'EOF'
obj-m := kotesh_stack_overflow.o
all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules
modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules_install
clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) clean
EOF
```

### Step 3: Update recipe
```bash
cat > $PANIC_DIR/kotesh-panic-driver.bb << 'EOF'
SUMMARY = "Kotesh panic demo"
LICENSE = "CLOSED"
inherit module
SRC_URI = "file://kotesh_stack_overflow.c file://Makefile"
S = "${WORKDIR}"
KERNEL_MODULE_AUTOLOAD += "kotesh_stack_overflow"
EOF
```

### Step 4: Enable DTS node
```bash
nano $DTS
# kotesh-stack { compatible = "kotesh,stack-overflow"; status = "okay"; };
# (all other panic nodes: status = "disabled")
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU
```

### Expected output
```
[    x.x] KOTESH_STACK: probe called
[    x.x] KOTESH_STACK: starting infinite recursion...
[    x.x] KOTESH_STACK: depth=0
[    x.x] KOTESH_STACK: depth=1
[    x.x] KOTESH_STACK: depth=2
...
[    x.x] KOTESH_STACK: depth=9

Insufficient stack space to handle exception!
ESR: 0x0000000096000047 -- DABT (current EL)
Task stack:     [0xffffffc009798000..0xffffffc00979c000]
Overflow stack: [0xffffff803fdc42c0..0xffffff803fdc52c0]
lr : infinite_recurse+0x3c/0x190 [kotesh_stack_overflow]

Kernel panic - not syncing: kernel stack overflow
CPU: 0 PID: 114 Comm: udevd Tainted: G O 5.15.194-yocto-standard #1
---[ end Kernel panic ]---
# QEMU FREEZES — always fatal, no recovery possible
```

### Key diagnostic fields
```
"Insufficient stack space to handle exception!"  ← ARM64 stack guard triggered
"kernel stack overflow"                           ← definitive message
lr : infinite_recurse+0x3c                        ← function that overflowed
Task stack / Overflow stack addresses shown       ← stack exhaustion confirmed
Always fatal — no [#N] counter, system hard stops
```

---

## Panic 03 — BUG_ON / WARN_ON

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_bugon.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

static int kotesh_bugon_probe(struct platform_device *pdev)
{
    pr_info("KOTESH_BUGON: probe called\n");
    pr_info("KOTESH_BUGON: triggering WARN_ON...\n");
    WARN_ON(1);
    pr_info("KOTESH_BUGON: survived WARN_ON — now BUG_ON...\n");
    BUG_ON(1);
    pr_info("KOTESH_BUGON: should not reach here\n");
    return 0;
}

static const struct of_device_id kotesh_bugon_ids[] = {
    { .compatible = "kotesh,bugon-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_bugon_ids);

static struct platform_driver kotesh_bugon_driver = {
    .probe = kotesh_bugon_probe,
    .driver = { .name = "kotesh_bugon", .of_match_table = of_match_ptr(kotesh_bugon_ids) },
};
module_platform_driver(kotesh_bugon_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS (same pattern)
```bash
# Makefile: obj-m := kotesh_bugon.o
# Recipe SRC_URI: file://kotesh_bugon.c
# KERNEL_MODULE_AUTOLOAD += "kotesh_bugon"
# DTS: kotesh-bugon { compatible = "kotesh,bugon-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU
```

### Expected output — WARN_ON (non-fatal):
```
[    x.x] KOTESH_BUGON: probe called
[    x.x] KOTESH_BUGON: triggering WARN_ON...

------------[ cut here ]------------
WARNING: CPU: 0 PID: 114 at drivers/kotesh_bugon.c:13 kotesh_bugon_probe+0x2c/0x4c [kotesh_bugon]
Modules linked in: kotesh_bugon(O+) ...
CPU: 0 PID: 114 Comm: udevd Tainted: G W O
Call trace:
 kotesh_bugon_probe+0x2c/0x4c [kotesh_bugon]
 platform_probe+0x70/0xf0
---[ end trace abcdef1234567890 ]---

[    x.x] KOTESH_BUGON: survived WARN_ON — now BUG_ON...
```

### Expected output — BUG_ON (fatal):
```
------------[ cut here ]------------
kernel BUG at drivers/kotesh_bugon.c:15!
Internal error: Oops - BUG: 00000000f2000800 [#1] PREEMPT SMP
pc : kotesh_bugon_probe+0x38/0x4c [kotesh_bugon]
Kernel panic - not syncing: Fatal exception
```

### Key diagnostic fields
```
WARN_ON:  "WARNING:" + Tainted "W"  → non-fatal, continues
BUG_ON:   "kernel BUG at file:line" → always fatal
WARN_ON taint flag "W" stays in kernel until reboot
```

---

## Panic 04 — Divide by Zero

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_divzero.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>

static int kotesh_divzero_probe(struct platform_device *pdev)
{
    volatile int a = 100, b = 0, result;
    pr_info("KOTESH_DIVZERO: probe called\n");
    pr_info("KOTESH_DIVZERO: about to divide 100 by 0...\n");
    result = a / b;
    pr_info("KOTESH_DIVZERO: result=%d (should not reach)\n", result);
    return 0;
}

static const struct of_device_id kotesh_divzero_ids[] = {
    { .compatible = "kotesh,divzero-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_divzero_ids);

static struct platform_driver kotesh_divzero_driver = {
    .probe = kotesh_divzero_probe,
    .driver = { .name = "kotesh_divzero", .of_match_table = of_match_ptr(kotesh_divzero_ids) },
};
module_platform_driver(kotesh_divzero_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_divzero.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_divzero"
# DTS: kotesh-divzero { compatible = "kotesh,divzero-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU
```

### Expected output (ARM64 specific)
```
[    x.x] KOTESH_DIVZERO: probe called
[    x.x] KOTESH_DIVZERO: about to divide 100 by 0...

Unexpected kernel BRK exception at EL1
Internal error: BRK handler: 00000000f20003e8 [#1] PREEMPT SMP
pc : kotesh_divzero_probe+0x34/0x38 [kotesh_divzero]

Kernel panic - not syncing: BRK handler: unexpected BRK exception in kernel
```

### ⚠️ ARM64 vs x86 difference — CRITICAL for interview
```
x86:   "divide error: 0000" — hardware trap #DE
ARM64: "Unexpected kernel BRK exception at EL1"
       BRK handler: 00000000f20003e8  ← f20003e8 = BRK #0x3e80 opcode

ARM64 has NO hardware divide-by-zero trap.
Compiler inserts: BRK #0x3e80 before division
If divisor is 0 at runtime → BRK fires → kernel handler
```

---

## Panic 05 — Hung Task

### Step 1: Create driver
```bash
cat > $PANIC_DIR/files/kotesh_hungtask.c << 'EOF'
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/delay.h>

static int kotesh_hungtask_probe(struct platform_device *pdev)
{
    pr_info("KOTESH_HUNG: probe called\n");
    pr_info("KOTESH_HUNG: entering infinite loop — will trigger hung task...\n");
    while (1) {
        msleep(1000);
    }
    return 0;
}

static const struct of_device_id kotesh_hungtask_ids[] = {
    { .compatible = "kotesh,hungtask-driver" }, { }
};
MODULE_DEVICE_TABLE(of, kotesh_hungtask_ids);

static struct platform_driver kotesh_hungtask_driver = {
    .probe = kotesh_hungtask_probe,
    .driver = { .name = "kotesh_hung", .of_match_table = of_match_ptr(kotesh_hungtask_ids) },
};
module_platform_driver(kotesh_hungtask_driver);
MODULE_LICENSE("GPL");
EOF
```

### Step 2-4: Makefile / Recipe / DTS
```bash
# Makefile: obj-m := kotesh_hungtask.o
# KERNEL_MODULE_AUTOLOAD += "kotesh_hungtask"
# DTS: kotesh-hung { compatible = "kotesh,hungtask-driver"; status = "okay"; };
dtc -I dts -O dtb -o $DTB $DTS
```

### Step 5: Build and boot
```bash
MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate
MACHINE=qemuarm64 bitbake core-image-minimal
# Boot QEMU — login as root immediately
```

### Step 6: After login, trigger faster timeout
```bash
# Reduce hung task timeout from 120s to 30s:
echo 30 > /proc/sys/kernel/hung_task_timeout_secs
cat /proc/sys/kernel/hung_task_timeout_secs
# 30

# Wait 30 seconds and watch dmesg:
dmesg -w
```

### Expected output
```
[    5.230088] KOTESH_HUNG: probe called
[    5.230421] KOTESH_HUNG: entering infinite loop — will trigger hung task...

# ~180 seconds later (udevd timeout):
[   65.930216] udevd[110]: worker [116] /devices/platform/kotesh-hung is taking a long time
[  186.108439] udevd[110]: worker [116] /devices/platform/kotesh-hung timeout; kill it
[  186.110680] udevd[110]: seq 625 '/devices/platform/kotesh-hung' killed

# With hung_task_timeout_secs=30 set after login:
INFO: task udevd:116 blocked for more than 30 seconds.
      Not tainted 5.15.194 #1
"echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Call trace:
 __switch_to+0x174/0x1d0
 schedule+0xa8/0x100
 schedule_timeout+0x200/0x2a0
 msleep+0x40/0x60
 kotesh_hungtask_probe+0x2c/0x40 [kotesh_hungtask]
 platform_probe+0x70/0xf0
 really_probe.part.0+0x94/0x310
```

### Key diagnostic fields
```
"worker [N] /devices/platform/kotesh-hung is taking a long time" ← udevd detects
"worker [N] timeout; kill it"                                    ← udevd kills worker
"INFO: task blocked for more than N seconds"                     ← kernel hung detector
Call trace shows msleep → kotesh_hungtask_probe                  ← blocking call site
NOT fatal — system survives, udevd worker killed only
```

### After boot checks
```bash
cat /proc/sys/kernel/hung_task_timeout_secs
# 0 (not set in this kernel — CONFIG_DETECT_HUNG_TASK not enabled)
# OR 120 (default if CONFIG is set)

# Check if udevd recovered:
ps aux | grep udevd
# udevd still running (spawned new worker)
```

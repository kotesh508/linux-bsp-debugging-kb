# BSP Lab — Debug Commands Master Reference
# Kotesh S | github.com/kotesh408
# Purpose: Quick lookup of debug commands by issue type
# Updated: March 2026

---

## HOW TO USE THIS FILE

When you see an issue:
1. Identify the category (NULL pointer / memory / timer / module / etc.)
2. Jump to that section
3. Run the commands in order
4. Cross-reference with issue .md files

---

# ═══════════════════════════════════════════════
# SECTION 1 — MODULE LOAD / UNLOAD ISSUES
# ═══════════════════════════════════════════════

## 1.1 — Check if module loaded
```bash
lsmod | grep <module_name>
# refcount = 0 → loaded, not in use
# refcount = 1 → loaded, something using it
# no output    → not loaded
```

## 1.2 — Load module with full error output
```bash
sudo insmod <module>.ko
echo "exit code: $?"
# exit code 0  = success
# exit code 1  = failed — check dmesg
```

## 1.3 — Module stuck / insmod hanging
```bash
# Find hung insmod process
ps aux | grep insmod

# Find which process holds module
sudo lsof | grep <module_name>

# Check refcount
cat /sys/module/<module_name>/refcnt

# Kill hung insmod
sudo kill -9 <PID>

# Force remove
sudo rmmod <module_name>
```

## 1.4 — Check module dependencies
```bash
modinfo <module>.ko
modinfo <module>.ko | grep depends
```

## 1.5 — Check module parameters
```bash
modinfo <module>.ko | grep parm
cat /sys/module/<module_name>/parameters/<param>
```

---

# ═══════════════════════════════════════════════
# SECTION 2 — KERNEL CRASH / OOPS ANALYSIS
# ═══════════════════════════════════════════════

## 2.1 — Capture crash immediately
```bash
dmesg | tail -40
dmesg | grep -B2 -A30 "BUG:\|Oops:\|unable to handle"
```

## 2.2 — NULL pointer dereference (x86)
```bash
# Key lines to look for:
dmesg | grep "BUG: kernel NULL"
# BUG: kernel NULL pointer dereference, address: 0000000000000000

dmesg | grep "#PF"
# #PF: supervisor write access  → kernel tried to WRITE to bad address
# #PF: supervisor read access   → kernel tried to READ from bad address
# error_code(0x0002)            → write fault, page not present
# error_code(0x0000)            → read fault, page not present

dmesg | grep "RIP:"
# RIP: 0010:function+0xOFFSET   → exact crash location
```

## 2.3 — NULL pointer dereference (ARM64 / QEMU)
```bash
dmesg | grep "Unable to handle kernel NULL"
dmesg | grep "ESR\|EC =\|WnR"
# WnR = 1 → Write fault
# WnR = 0 → Read fault
# EC = 0x25 → Data Abort
```

## 2.4 — Decode crash offset to source line
```bash
# Method 1 — objdump
objdump -d <module>.o | grep -A20 "<function_name>"
# Find offset (e.g. +0x16) in assembly output

# Method 2 — addr2line
addr2line -e <module>.o -a 0x16

# Method 3 — gdb
gdb <module>.o
(gdb) list *(function+0x16)
```

## 2.5 — Full call trace analysis
```bash
dmesg | grep -A20 "Call Trace"
# Read bottom to top — deepest call at top
# do_syscall → load_module → do_init_module → my_init → CRASH
```

## 2.6 — Check taint flags
```bash
dmesg | grep "Tainted:"
# G  = proprietary module loaded
# O  = out-of-tree module
# W  = WARN_ON triggered
# P  = proprietary module
# E  = unsigned module
```

---

# ═══════════════════════════════════════════════
# SECTION 3 — MEMORY ISSUES
# ═══════════════════════════════════════════════

## 3.1 — Monitor memory usage
```bash
watch -n1 grep MemFree /proc/meminfo
# Dropping continuously → memory leak

grep MemFree /proc/meminfo   # before
# ... run driver operations ...
grep MemFree /proc/meminfo   # after
# Compare — should be same ±200kB
```

## 3.2 — Detect memory leak
```bash
# Method 1 — load/unload cycle test
for i in $(seq 1 10); do
    sudo insmod <module>.ko
    sleep 0.2
    sudo rmmod <module>
done
grep MemFree /proc/meminfo
# MemFree stable = no leak

# Method 2 — kmemleak (requires CONFIG_DEBUG_KMEMLEAK=y)
sudo cat /sys/kernel/debug/kmemleak
# Output = leaked allocations with stack trace
# No output = no leak detected

# Trigger kmemleak scan manually
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak
```

## 3.3 — Check kernel memory config
```bash
zcat /proc/config.gz | grep CONFIG_KASAN
zcat /proc/config.gz | grep CONFIG_DEBUG_KMEMLEAK
zcat /proc/config.gz | grep CONFIG_DEBUG_PAGEALLOC
zcat /proc/config.gz | grep CONFIG_SLUB_DEBUG
```

## 3.4 — OOM analysis
```bash
dmesg | grep -i "out of memory\|OOM\|Kill process"
dmesg | grep "page allocation failure"

# Check current memory state
cat /proc/meminfo | grep -E "MemFree|MemAvailable|Slab|SUnreclaim"
free -m

# High Slab value = kernel memory leak
# High SUnreclaim = unreclaimable kernel allocations
```

## 3.5 — Double free / use-after-free detection
```bash
# SLUB poison values in registers = double free detected
dmesg | grep "dead0000"
# dead000000000100 and dead000000000200 = SLUB poison = freed memory

# With KASAN enabled
dmesg | grep -i "kasan\|use-after-free\|double-free"
```

---

# ═══════════════════════════════════════════════
# SECTION 4 — TIMER / HRTIMER ISSUES
# ═══════════════════════════════════════════════

## 4.1 — Verify timer is firing
```bash
# Watch live dmesg for timer messages
dmesg -w | grep <keyword> &
sleep 3
kill %1

# Check timestamps — should be regular intervals
dmesg | grep "Data updated" | tail -10
# [214.350] ... to 189
# [214.450] ... to 190   ← exactly 100ms apart
```

## 4.2 — Timer not firing — check assignment
```bash
grep -n "my_timer.function\|hrtimer_start\|hrtimer_init" <driver>.c
# All 3 must be present:
# hrtimer_init(&timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL)
# timer.function = callback
# hrtimer_start(&timer, ms_to_ktime(100), HRTIMER_MODE_REL)
```

## 4.3 — Module hangs on insmod with timer
```bash
# Background the insmod — don't let it block terminal
sudo insmod <module>.ko &
sleep 2
dmesg | grep <keyword> | tail -10

# If timer floods log — reduce interval or limit count in callback
```

## 4.4 — Clean timer shutdown
```bash
# Verify timer cancelled before rmmod
# In driver: hrtimer_cancel(&timer) must be in exit()
# If missing → rmmod hangs or crashes

dmesg | grep "Exiting"   # confirms exit() ran
```

---

# ═══════════════════════════════════════════════
# SECTION 5 — SPINLOCK / LOCKING ISSUES
# ═══════════════════════════════════════════════

## 5.1 — Correct lock/unlock pairs
```bash
# Always paired:
# spin_lock_irqsave(&lock, flags)    ← saves IRQ state
# spin_unlock_irqrestore(&lock, flags) ← restores IRQ state

# Common mistake:
# spin_unlock_irqsave() ← DOES NOT EXIST
# spin_lock_irqrestore() ← DOES NOT EXIST
```

## 5.2 — Deadlock detection
```bash
dmesg | grep -i "deadlock\|lockdep\|circular"
zcat /proc/config.gz | grep CONFIG_LOCKDEP
# CONFIG_LOCKDEP=y → kernel detects deadlocks automatically
```

## 5.3 — Check lockdep report
```bash
dmesg | grep -A20 "WARNING: possible circular locking"
dmesg | grep -A20 "WARNING: possible recursive locking"
```

---

# ═══════════════════════════════════════════════
# SECTION 6 — DTS / DRIVER PROBE ISSUES
# ═══════════════════════════════════════════════

## 6.1 — Driver not probing
```bash
# Check module loaded
lsmod | grep <driver>

# Check dmesg for probe message
dmesg | grep -i "<driver_name>\|probe"

# Check device registered
ls /sys/bus/platform/devices/ | grep <device>

# Check driver registered
ls /sys/bus/platform/drivers/ | grep <driver>

# Check binding
ls /sys/bus/platform/drivers/<driver>/
# Device symlink present = bound
# No symlink = not bound
```

## 6.2 — Check compatible string match
```bash
# What DTS says
cat /proc/device-tree/<node>/compatible

# What driver expects — check source
grep "compatible" <driver>.c

# Must match EXACTLY — case sensitive, character by character
```

## 6.3 — Probe deferral
```bash
cat /sys/kernel/debug/devices_deferred
# Lists all deferred devices and reason

ls /sys/bus/platform/devices/<device>/waiting_for_supplier
# File exists = probe deferred, waiting for dependency
```

## 6.4 — Check error codes in probe
```bash
dmesg | grep "probe of.*failed"
# error=-2  → ENOENT  → missing DTS property (clock, reg, compatible)
# error=-19 → ENODEV  → device not found (regulator, hardware absent)
# error=-22 → EINVAL  → wrong value in DTS
# error=-11 → EAGAIN  → probe deferred
# error=-16 → EBUSY   → resource already in use
```

---

# ═══════════════════════════════════════════════
# SECTION 7 — KERNEL CONFIG ISSUES
# ═══════════════════════════════════════════════

## 7.1 — Check if config is enabled
```bash
zcat /proc/config.gz | grep CONFIG_<FEATURE>
# CONFIG_FEATURE=y   → built-in
# CONFIG_FEATURE=m   → module
# # CONFIG_FEATURE is not set → disabled
```

## 7.2 — Common debug configs to check
```bash
zcat /proc/config.gz | grep CONFIG_KASAN          # memory error detector
zcat /proc/config.gz | grep CONFIG_DEBUG_KMEMLEAK # memory leak detector
zcat /proc/config.gz | grep CONFIG_LOCKDEP         # deadlock detector
zcat /proc/config.gz | grep CONFIG_DEBUG_STACKOVERFLOW
zcat /proc/config.gz | grep CONFIG_PANIC_ON_OOPS
zcat /proc/config.gz | grep CONFIG_DETECT_HUNG_TASK
```

## 7.3 — API returns -ENOSYS
```bash
dmesg | grep "Unknown symbol"
# Unknown symbol gpio_request → CONFIG_GPIOLIB=n

# Find which config enables an API
grep -r "gpio_request" include/linux/gpio.h
# → #ifdef CONFIG_GPIOLIB
```

---

# ═══════════════════════════════════════════════
# SECTION 8 — BOOT ISSUES (QEMU)
# ═══════════════════════════════════════════════

## 8.1 — Identify boot stage from panic
```bash
# Stage 1 — No console output → check -append console=
# Stage 2 — VFS panic → check root=/dev/vda
# Stage 3 — Mount fail → check CONFIG_EXT4_FS=y
# Stage 4 — No virtio → check CONFIG_VIRTIO_BLK=y
# Stage 5 — No init → check /sbin/init exists in rootfs
```

## 8.2 — Check DTB
```bash
file ~/dtstest/kotesh-test.dtb
# Should say: Device Tree Blob version 17

# Rebuild DTB after DTS change
dtc -I dts -O dtb -o $DTB $DTS
```

## 8.3 — Check device tree at runtime (inside QEMU)
```bash
ls /proc/device-tree/
cat /proc/device-tree/<node>/compatible
cat /proc/device-tree/<node>/status
ls /proc/device-tree/<node>/          # see all properties
```

---

# ═══════════════════════════════════════════════
# SECTION 9 — GENERAL KERNEL DEBUG COMMANDS
# ═══════════════════════════════════════════════

## 9.1 — dmesg filtering
```bash
dmesg | tail -20                          # last 20 lines
dmesg | grep -i "error\|fail\|warn"       # errors only
dmesg | grep -v "e1000e"                  # suppress noise
dmesg -w                                  # live watch
dmesg --level=err,warn                    # errors and warnings only
sudo dmesg -n 7                           # set log level to debug
dmesg -T                                  # human readable timestamps
```

## 9.2 — /proc filesystem
```bash
cat /proc/meminfo                  # memory statistics
cat /proc/interrupts               # IRQ counters
cat /proc/devices                  # registered char/block devices
cat /proc/modules                  # loaded modules
cat /proc/sys/kernel/panic_on_oops # 0=survive, 1=panic on oops
cat /proc/uptime                   # system uptime — still running after oops?
```

## 9.3 — /sys filesystem
```bash
ls /sys/bus/platform/devices/      # all platform devices
ls /sys/bus/platform/drivers/      # all platform drivers
ls /sys/class/                     # device classes
cat /sys/module/<module>/refcnt    # module reference count
ls /sys/kernel/debug/              # debug filesystem
```

## 9.4 — Compiler warnings for debug
```bash
make W=1                           # extra warnings including stack frame size
make C=1                           # sparse static analysis (__user pointer checks)
make W=1 2>&1 | grep "stack frame" # find large stack frames
make C=1 2>&1 | grep "warning"     # find __user pointer misuse
```

---

# ═══════════════════════════════════════════════
# QUICK REFERENCE — ISSUE → FIRST COMMAND
# ═══════════════════════════════════════════════

| Symptom | First Command |
|---|---|
| insmod Killed | `dmesg \| grep "BUG:\|Oops:"` |
| insmod hangs | `ps aux \| grep insmod` |
| Module won't unload | `cat /sys/module/<name>/refcnt` |
| Timer not firing | `grep -n "timer.function\|hrtimer_start" <driver>.c` |
| No probe message | `cat /sys/kernel/debug/devices_deferred` |
| Driver silent | `cat /proc/device-tree/<node>/compatible` |
| Memory dropping | `watch grep MemFree /proc/meminfo` |
| -ENOSYS error | `zcat /proc/config.gz \| grep CONFIG_<FEATURE>` |
| Crash on write | `dmesg \| grep "#PF: supervisor write"` |
| Crash on read | `dmesg \| grep "#PF: supervisor read"` |
| Stack overflow | `make W=1 \| grep "stack frame"` |
| Double free | `dmesg \| grep "dead0000"` |
| Probe deferred | `cat /sys/kernel/debug/devices_deferred` |
| IRQ not firing | `cat /proc/interrupts \| grep <name>` |
| Boot panic | `dmesg \| grep "Kernel panic"` |

---

*Kotesh S — BSP Lab Debug Reference — March 2026*
*Update this file each time you discover a new debug command*

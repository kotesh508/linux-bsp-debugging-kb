# Panic Issue 05 — Hung Task / Soft Lockup

---

## 📋 Category
`03_Panic_Analysis`

## 🔴 Symptom Output

```
[    5.230088] KOTESH_HUNG: probe called
[    5.230421] KOTESH_HUNG: entering infinite loop — will trigger hung task...

[   65.930216] udevd[110]: worker [116] /devices/platform/kotesh-hung is taking a long time
[  186.108439] udevd[110]: worker [116] /devices/platform/kotesh-hung timeout; kill it
[  186.110680] udevd[110]: seq 625 '/devices/platform/kotesh-hung' killed
```

With `hung_task_timeout_secs` enabled, the kernel also prints:
```
INFO: task udevd:116 blocked for more than 120 seconds.
      Not tainted 5.15.194 #1
"echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Call trace:
 __switch_to+0x...
 schedule+0x...
 schedule_timeout+0x...
 msleep+0x...
 kotesh_hungtask_probe+0x.../0x... [kotesh_hungtask]
 platform_probe+0x...
```

---

## 🔍 Panic Type
**Hung Task** — a kernel thread blocked/looping for longer than the hung task timeout (default 120 seconds). This is **not a crash** — the kernel detects it and prints a warning.

---

## 🔎 How to Read This Output

### 1. udevd Worker Timeout — What we saw
```
[   65.930216] udevd[110]: worker [116] /devices/platform/kotesh-hung is taking a long time
```
- udevd detected its worker thread handling `kotesh-hung` is stuck
- Worker was stuck inside `probe()` which never returned
- udevd has its own timeout mechanism (separate from kernel hung_task)

```
[  186.108439] udevd[110]: worker [116] /devices/platform/kotesh-hung timeout; kill it
[  186.110680] udevd[110]: seq 625 '/devices/platform/kotesh-hung' killed
```
- After ~180 seconds udevd killed the stuck worker
- This is udevd's self-protection — not kernel hung_task watchdog

### 2. Kernel Hung Task Watchdog (CONFIG_DETECT_HUNG_TASK)
The kernel's hung task detector fires when `hung_task_timeout_secs` is set:
```bash
# Reduce timeout to trigger faster
echo 30 > /proc/sys/kernel/hung_task_timeout_secs
```

Expected kernel output:
```
INFO: task udevd:116 blocked for more than 30 seconds.
Call trace:
 msleep+0x...
 kotesh_hungtask_probe+0x... [kotesh_hungtask]
 platform_probe+0x...
```

### 3. Key Difference — Hung Task vs Soft Lockup vs Hard Lockup

| Type | Cause | Detects | Fatal? |
|---|---|---|---|
| Hung Task | Task blocked in `D` state or sleeping loop | `khungtaskd` watchdog | ❌ Warning only |
| Soft Lockup | CPU spinning >10s without scheduling | Soft lockup watchdog | ⚠️ Warning/panic |
| Hard Lockup | CPU spinning >20s with IRQs disabled | NMI watchdog | ✅ Always panic |

Our driver uses `msleep()` which is **interruptible sleep** — this is a hung
task, not a lockup. The CPU is free to schedule other tasks.

---

## 🔍 Root Cause

```c
static int kotesh_hungtask_probe(struct platform_device *pdev)
{
    pr_info("KOTESH_HUNG: probe called\n");
    pr_info("KOTESH_HUNG: entering infinite loop...\n");

    /* Infinite loop with sleep — never returns from probe */
    while (1) {
        msleep(1000);   /* sleep 1 second, repeat forever */
    }

    return 0;   /* never reached */
}
```

The `probe()` function **never returns**. The udevd worker thread that called
`probe()` is stuck forever. The kernel's hung task watchdog eventually detects
the thread has been sleeping/blocked for more than `hung_task_timeout_secs`.

**Why msleep doesn't help:**
- `msleep()` puts the thread to sleep — goes into `TASK_INTERRUPTIBLE` state
- Thread wakes up after 1 second, loops, sleeps again
- Thread never returns from `probe()` → udevd worker is permanently blocked
- This is NOT a soft lockup — CPU is free, just this thread is stuck

---

## ✅ Fix

### Option 1: Use a kernel thread for long-running work
```c
#include <linux/kthread.h>

static struct task_struct *kotesh_thread;

static int kotesh_worker(void *data)
{
    while (!kthread_should_stop()) {
        pr_info("KOTESH_HUNG: working...\n");
        msleep(1000);
    }
    return 0;
}

static int kotesh_hungtask_probe(struct platform_device *pdev)
{
    pr_info("KOTESH_HUNG: probe called\n");

    /* Start background thread — probe returns immediately */
    kotesh_thread = kthread_run(kotesh_worker, NULL, "kotesh-worker");
    if (IS_ERR(kotesh_thread))
        return PTR_ERR(kotesh_thread);

    pr_info("KOTESH_HUNG: probe successful\n");
    return 0;   /* returns immediately! */
}

static int kotesh_hungtask_remove(struct platform_device *pdev)
{
    kthread_stop(kotesh_thread);
    return 0;
}
```

### Option 2: Use a workqueue for deferred work
```c
#include <linux/workqueue.h>

static void kotesh_work_fn(struct work_struct *work)
{
    pr_info("KOTESH_HUNG: deferred work running\n");
}

static DECLARE_WORK(kotesh_work, kotesh_work_fn);

static int kotesh_hungtask_probe(struct platform_device *pdev)
{
    schedule_work(&kotesh_work);  /* defer — probe returns immediately */
    return 0;
}
```

**Rule:** `probe()` must always return promptly. Never block or loop in probe.

---

## 🧠 Interview Explanation

> A hung task occurs when a kernel thread stays blocked or in an infinite sleep loop for longer than `hung_task_timeout_secs` (default 120s). The kernel's `khungtaskd` daemon monitors for threads in uninterruptible sleep (`D` state) or repeatedly sleeping without making progress. When detected, it prints `INFO: task <name> blocked for more than N seconds` with a call trace showing where the thread is stuck. This is different from a soft lockup (CPU spinning without scheduling) or hard lockup (CPU with IRQs disabled). In BSP driver development, a common mistake is performing long operations or waiting in `probe()` — this blocks the udevd worker thread that called probe, and eventually triggers a hung task warning. The fix is to use kernel threads or workqueues for any long-running work, ensuring probe returns quickly.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_hungtask.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/kotesh-panic-driver.bb` |

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
# 1. Boot QEMU with only kotesh-hung DTS node enabled
# 2. After login reduce timeout:
echo 30 > /proc/sys/kernel/hung_task_timeout_secs

# 3. Wait 30 seconds — observe:
# INFO: task udevd:XXX blocked for more than 30 seconds
# Call trace showing msleep -> kotesh_hungtask_probe

# 4. Or observe udevd timeout after ~180 seconds:
# udevd: worker [XXX] /devices/platform/kotesh-hung is taking a long time
# udevd: worker [XXX] /devices/platform/kotesh-hung timeout; kill it
```

---

## ✅ Key Diagnostic Commands

```bash
# Check current hung task timeout
cat /proc/sys/kernel/hung_task_timeout_secs

# Reduce timeout for faster detection
echo 30 > /proc/sys/kernel/hung_task_timeout_secs

# Disable hung task warnings
echo 0 > /proc/sys/kernel/hung_task_timeout_secs

# Check for D-state (uninterruptible sleep) processes
ps aux | grep ' D '

# Check kernel threads
ps aux | grep '\[k'
```

---

## 📌 Full Panic Comparison So Far

| # | Panic Type | Key Signature | Fatal? |
|---|---|---|---|
| 01 | NULL Pointer | `Unable to handle kernel NULL pointer dereference` | Oops |
| 02 | Stack Overflow | `kernel stack overflow` | ✅ Always |
| 03 | WARN_ON | `cut here` + `WARNING:` | ❌ No |
| 03 | BUG_ON | `kernel BUG at file:line` | ✅ Yes |
| 04 | Divide by Zero | `Unexpected kernel BRK exception at EL1` | ✅ Yes |
| 05 | Hung Task | `INFO: task blocked for more than N seconds` | ❌ Warning |

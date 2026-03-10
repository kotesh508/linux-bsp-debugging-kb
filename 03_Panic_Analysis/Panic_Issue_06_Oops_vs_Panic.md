# Panic Issue 06 — Kernel Oops vs Panic (panic_on_oops)

---

## 📋 Category
`03_Panic_Analysis`

---

## 🔴 Part 1 — Oops WITHOUT panic_on_oops (system survives)

```
[    5.230197] KOTESH_NULL: probe called
[    5.230538] KOTESH_NULL: about to dereference NULL pointer...
[    5.262461] Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
[    5.266622] pc : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
...
[    5.381875] udevd[110]: worker [115] terminated by signal 11 (Segmentation fault)
[    5.382531] udevd[110]: worker [115] failed while handling '/devices/platform/kotesh-null'

qemuarm64 login: root       ← SYSTEM SURVIVED!
root@qemuarm64:~# cat /proc/uptime
146.28 133.06
root@qemuarm64:~# echo "System survived oops!"
System survived oops!
```

**Observation:** Oops printed, udevd worker killed, but system continued booting
and reached login prompt. The kernel kept running.

---

## 🔴 Part 2 — Panic WITH panic_on_oops=1 (system halts)

```
root@qemuarm64:~# echo 1 > /proc/sys/kernel/panic_on_oops
root@qemuarm64:~# echo c > /proc/sysrq-trigger
[  156.724427] sysrq: Trigger a crash
[  156.725732] Kernel panic - not syncing: sysrq triggered crash
[  156.726605] Kernel Offset: disabled
[  156.727060] CPU features: 0x4,400800d1,00000842
[  156.727855] Memory Limit: none
[  156.728440] ---[ end Kernel panic - not syncing: sysrq triggered crash ]---
```

**Observation:** With `panic_on_oops=1` set, any fatal kernel exception becomes
a hard panic. QEMU froze — no login prompt, no recovery.

---

## 🔍 Panic Type
**Kernel Oops** — a recoverable kernel error (by default). Becomes a **Kernel
Panic** when `panic_on_oops=1` is set.

---

## 🔎 What is a Kernel Oops?

An Oops is the kernel's way of reporting a serious but potentially survivable
error. The kernel prints diagnostics (registers, call trace, code dump) then
attempts to continue running.

### Oops signature:
```
Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
```

| Field | Meaning |
|---|---|
| `0000000096000045` | ESR — the fault code (ARM64 data abort) |
| `[#1]` | This is the 1st Oops — if `[#2]` appears kernel may panic anyway |
| `PREEMPT SMP` | Kernel config flags |

### What happens after an Oops:
1. Kernel prints registers + call trace
2. Kills the faulting process/thread (SIGKILL)
3. Marks kernel as **Tainted** (`G` flag)
4. **Continues running** if `panic_on_oops=0` (default)
5. **Hard panics** if `panic_on_oops=1`

---

## 🔎 Oops vs Panic — Key Differences

| Feature | Oops | Panic |
|---|---|---|
| Keyword | `Internal error: Oops:` | `Kernel panic - not syncing:` |
| System survives? | ✅ Yes (default) | ❌ No — always fatal |
| Process killed? | ✅ Faulting process | N/A — whole system halts |
| Taint flag set? | ✅ Yes (`D` flag added) | N/A |
| Controlled by | `panic_on_oops` sysctl | N/A |
| Recovery possible? | Yes — other processes keep running | No — requires reboot |

---

## 🔎 How panic_on_oops Works

### At runtime (temporary):
```bash
# Enable — oops becomes panic
echo 1 > /proc/sys/kernel/panic_on_oops

# Disable — oops is survivable (default)
echo 0 > /proc/sys/kernel/panic_on_oops

# Check current value
cat /proc/sys/kernel/panic_on_oops
```

### Persistent (survives reboot):
```bash
# Add to /etc/sysctl.conf
echo "kernel.panic_on_oops=1" >> /etc/sysctl.conf
sysctl -p
```

### Via kernel command line (boot time):
```
-append "console=ttyAMA0 root=/dev/vda rw panic_on_oops=1"
```

### In Yocto kernel config:
```
CONFIG_PANIC_ON_OOPS=y        # always panic on oops
CONFIG_PANIC_ON_OOPS_VALUE=1
```

---

## 🔎 Taint Flags — What They Mean

The `Tainted:` line in an Oops tells you the kernel's health history:

```
CPU: 0 PID: 115 Comm: udevd Tainted: G           O      5.15.194
```

| Flag | Meaning |
|---|---|
| `G` | All modules have GPL-compatible license |
| `O` | Out-of-tree module loaded |
| `W` | WARN_ON fired previously |
| `D` | Kernel self-detected as DYING (previous Oops) |
| `P` | Proprietary module loaded |
| `C` | Staging driver loaded |

In our case `G O` = GPL kernel + out-of-tree modules loaded (our custom drivers).

---

## 🔎 panic_on_oops Use Cases in BSP Work

| Scenario | Setting | Reason |
|---|---|---|
| Development / debugging | `0` (default) | Survive oops, collect dmesg, fix driver |
| Production / safety systems | `1` | Never run with corrupt kernel state |
| Automated test / CI | `1` | Fail fast — don't mask errors |
| Embedded with watchdog | `1` + `panic_timeout=5` | Auto-reboot after panic |

### Combine with panic_timeout for auto-reboot:
```bash
# Panic and reboot after 5 seconds
echo 1 > /proc/sys/kernel/panic_on_oops
echo 5 > /proc/sys/kernel/panic_timeout
```

---

## 🔎 sysrq — Emergency Kernel Commands

The `sysrq-trigger` interface sends emergency commands directly to the kernel:

```bash
# Enable all sysrq commands
echo 1 > /proc/sys/kernel/sysrq

# Force immediate crash/panic (used in this lab)
echo c > /proc/sysrq-trigger

# Show all running tasks
echo t > /proc/sysrq-trigger

# Sync filesystems
echo s > /proc/sysrq-trigger

# Unmount filesystems
echo u > /proc/sysrq-trigger

# Reboot immediately
echo b > /proc/sysrq-trigger

# Show memory info
echo m > /proc/sysrq-trigger
```

`echo c` sends a direct NULL pointer crash in kernel context — guaranteed panic
because it runs at EL1 (kernel mode), not inside a userspace process.

---

## 🧠 Why Our Driver's Oops Survived

The Oops from `kotesh_null_ptr` happened during **module load from udevd**:

```
Call trace:
 kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
 platform_probe+0x70/0xf0
 ...
 load_module+0x2240/0x2970
 __do_sys_finit_module+0xa8/0xf0   ← syscall from udevd
 __arm64_sys_finit_module+0x28/0x40
 invoke_syscall+0x5c/0x130
 el0_svc+0x28/0x80                 ← EL0 = came from userspace!
 el0t_64_sync+0x1a0/0x1a4
```

Key: `el0t_64_sync` = Exception Level 0 trap from userspace. The kernel was
serving a syscall on behalf of udevd — when it faulted, only the **udevd worker
thread** was killed. The kernel itself was unaffected.

If the crash had happened in pure kernel context (interrupt handler, kernel
thread, etc.) the oops would have been more likely to panic even without
`panic_on_oops=1`.

---

## 🧠 Interview Explanation

> A Kernel Oops is a non-fatal kernel error — the kernel detects a fault (like
> a NULL pointer dereference), prints registers and a call trace, kills the
> offending process, and continues running. By default `panic_on_oops=0` so the
> system survives. Setting `panic_on_oops=1` converts any Oops into a hard
> Kernel Panic — the system halts and must be rebooted. In production BSP work,
> `panic_on_oops=1` is often combined with `panic_timeout=N` so the system
> auto-reboots via watchdog after a fatal error. The `sysrq` interface is useful
> for testing panic behavior — `echo c > /proc/sysrq-trigger` forces an
> immediate kernel crash in kernel context, bypassing the userspace process
> protection that can let an Oops survive.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_null_ptr.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |

---

## 🖥️ QEMU Boot Commands

### Part 1 — Oops only (default):
```bash
qemu-system-aarch64 \
  -machine virt -cpu cortex-a57 -m 1024 -nographic \
  -kernel .../Image \
  -dtb .../kotesh-test.dtb \
  -append "console=ttyAMA0 root=/dev/vda rw" \
  -drive if=none,format=raw,file=.../core-image-minimal-qemuarm64.ext4,id=hd0 \
  -device virtio-blk-device,drive=hd0
```

### Part 2 — Trigger panic at runtime:
```bash
# After boot:
echo 1 > /proc/sys/kernel/panic_on_oops
echo c > /proc/sysrq-trigger
```

---

## 📌 Full Panic Comparison So Far

| # | Panic Type | Key Signature | Fatal? |
|---|---|---|---|
| 01 | NULL Pointer | `Unable to handle kernel NULL pointer dereference` | Oops (survivable) |
| 02 | Stack Overflow | `kernel stack overflow` | ✅ Always |
| 03 | WARN_ON | `cut here` + `WARNING:` | ❌ No |
| 03 | BUG_ON | `kernel BUG at file:line` | ✅ Yes |
| 04 | Divide by Zero | `Unexpected kernel BRK exception at EL1` | ✅ Yes |
| 05 | Hung Task | `INFO: task blocked for more than N seconds` | ❌ Warning |
| 06 | Oops → Panic | `Kernel panic - not syncing: sysrq triggered crash` | Depends on `panic_on_oops` |

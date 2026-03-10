# Panic Issue 03 — BUG_ON / WARN_ON (Kernel Assertion Failure)

---

## 📋 Category
`03_Panic_Analysis`

## 🔴 Panic Output

### WARN_ON — Warning (system continues)
```
[    8.418637] KOTESH_BUGON: triggering WARN_ON...
[    8.420706] ------------[ cut here ]------------
[    8.421479] WARNING: CPU: 0 PID: 117 at /usr/src/debug/kotesh-panic-driver/1.0-r0/kotesh_bugon.c:13 kotesh_bugon_probe+0x2c/0x4c [kotesh_bugon]
[    8.428563] CPU: 0 PID: 117 Comm: udevd Tainted: G           O      5.15.194-yocto-standard #1
[    8.431561] pc : kotesh_bugon_probe+0x2c/0x4c [kotesh_bugon]
[    8.443347] Call trace:
[    8.443829]  kotesh_bugon_probe+0x2c/0x4c [kotesh_bugon]
[    8.444508]  platform_probe+0x70/0xf0
...
[    8.455151] ---[ end trace 479e28f5c9ce9e8b ]---
# System CONTINUES after WARN_ON!
```

### BUG_ON — Hard Panic (system halts)
```
# BUG_ON would produce:
# kernel BUG at kotesh_bugon.c:18!
# Internal error: Oops - BUG: 0 [#1] PREEMPT SMP
# Kernel panic - not syncing: Fatal exception
```

---

## 🔍 Panic Type
**Kernel Assertion Failure** — explicit programmer assertion in driver code

- `WARN_ON(cond)` → prints warning + stack trace, system **continues**
- `BUG_ON(cond)`  → hard panic, system **halts**

---

## 🔎 How to Read This Output

### 1. WARN_ON Signature
```
------------[ cut here ]------------
WARNING: CPU: 0 PID: 117 at <file>:<line> <function> [<module>]
```
- `------------[ cut here ]------------` → always marks start of WARN_ON
- `WARNING:` → this is WARN_ON (not BUG_ON)
- `at kotesh_bugon.c:13` → exact source file and line number!
- `kotesh_bugon_probe+0x2c/0x4c` → exact function and offset

### 2. Source Location — Most Useful Field
```
WARNING: CPU: 0 PID: 117 at /usr/src/debug/kotesh-panic-driver/1.0-r0/kotesh_bugon.c:13
```
- Full path to source file: `kotesh_bugon.c`
- Line number: `13` → exactly where `WARN_ON(value == 0)` is in the code
- This is possible because Yocto builds with debug info

### 3. Tainted Flag
```
Tainted: G           O
```
- `G` = all modules are GPL licensed
- `O` = out-of-tree module loaded (our driver)
- `W` = WARN_ON was triggered (appears after warning fires)

### 4. WARN_ON vs BUG_ON Behavior
```
WARN_ON(value == 0):
  → Prints warning + call trace
  → Sets WARN tainted flag
  → System CONTINUES executing
  → "survived WARN_ON, continuing..." printed after

BUG_ON(value == 0):
  → Prints "kernel BUG at <file>:<line>!"
  → Internal error: Oops - BUG
  → Kernel panic - not syncing: Fatal exception
  → System HALTS immediately
```

---

## 🔍 Root Cause

```c
static int kotesh_bugon_probe(struct platform_device *pdev)
{
    int value = 0;

    /* WARN_ON — condition true → print warning, continue */
    WARN_ON(value == 0);                    /* line 13 — fires! */

    pr_info("survived WARN_ON, continuing...\n");  /* this executes */

    /* BUG_ON — condition true → hard panic */
    BUG_ON(value == 0);                     /* line 18 — panics! */

    pr_info("this never executes\n");
    return 0;
}
```

Both macros check if their condition is true:
- `WARN_ON(x)` expands to: if (x) { print warning + stack trace }
- `BUG_ON(x)` expands to: if (x) { BUG() } → triggers panic

---

## ✅ When to Use Each

```c
/* WARN_ON — use for unexpected but recoverable conditions */
WARN_ON(!irqs_disabled());          /* warn if IRQs not disabled */
WARN_ON(refcount < 0);              /* warn on negative refcount */

/* WARN_ON_ONCE — only print once, avoid log spam */
WARN_ON_ONCE(some_condition);

/* BUG_ON — use for truly unrecoverable conditions */
BUG_ON(ptr == NULL && must_exist);  /* panic if critical ptr missing */
BUG_ON(size > MAX_SIZE);            /* panic if corruption detected */

/* WARN — with custom message */
WARN(value < 0, "value=%d should not be negative!\n", value);

/* BUG — unconditional panic */
BUG();   /* always panics — used in unreachable code paths */
```

**Best practice for drivers:**
```c
/* Prefer returning error over BUG_ON in drivers */
if (!ptr) {
    dev_err(&pdev->dev, "critical ptr is NULL\n");
    return -EINVAL;   /* better than BUG_ON in most driver cases */
}
```

---

## 🧠 Interview Explanation

> `WARN_ON` and `BUG_ON` are kernel assertion macros. `WARN_ON(condition)` fires when the condition is true — it prints a warning message with the source file, line number, and call trace, then allows execution to continue. `BUG_ON(condition)` also fires when the condition is true but causes a hard kernel panic — execution stops immediately. In the dmesg output, WARN_ON is identified by `------------[ cut here ]------------` followed by `WARNING:`, while BUG_ON produces `kernel BUG at <file>:<line>!`. The source file and line number are printed directly, making these the easiest panics to debug. In driver development, prefer returning error codes over `BUG_ON` for recoverable conditions, and use `WARN_ON` to flag unexpected states that shouldn't stop the system.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_bugon.c` |
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

## ✅ Panic Analysis Cheat Sheet

| Field | Meaning |
|---|---|
| `------------[ cut here ]------------` | Start of WARN_ON output |
| `WARNING: CPU: X PID: Y at file:line` | WARN_ON fired — source location |
| `kernel BUG at file:line!` | BUG_ON fired — source location |
| `Tainted: G W O` | W = WARN was triggered |
| `---[ end trace XXXX ]---` | End of WARN_ON output |
| System continues after | WARN_ON — non-fatal |
| System halts after | BUG_ON — fatal panic |

---

## 📌 Full Comparison — WARN_ON vs BUG_ON vs NULL Ptr

| | WARN_ON | BUG_ON | NULL Ptr Deref |
|---|---|---|---|
| Trigger | Explicit condition check | Explicit condition check | Accidental bad access |
| Fatal? | ❌ No — continues | ✅ Yes — panics | ✅ Yes — oops/panic |
| Source location shown? | ✅ Yes — file + line | ✅ Yes — file + line | ✅ Partial — PC offset |
| Key signature | `cut here` + `WARNING:` | `kernel BUG at` | `Unable to handle` |
| Tainted flag | `W` added | None extra | None extra |
| Use case | Unexpected recoverable state | Unrecoverable corruption | Programming error |

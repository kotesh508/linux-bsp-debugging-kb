# Panic Issue 04 — Divide by Zero

---

## 📋 Category
`03_Panic_Analysis`

## 🔴 Panic Message

```
[    7.811844] KOTESH_DIVZERO: probe called
[    7.812517] KOTESH_DIVZERO: about to divide 100 by 0...
[    7.813973] Unexpected kernel BRK exception at EL1
[    7.815232] Internal error: BRK handler: 00000000f20003e8 [#1] PREEMPT SMP
[    7.820089] CPU: 0 PID: 119 Comm: udevd Tainted: G           O      5.15.194-yocto-standard #1
[    7.822253] pstate: 60000005 (nZCv daif -PAN -UAO -TCO -DIT -SSBS BTYPE=--)
[    7.823027] pc : kotesh_divzero_probe+0x34/0x38 [kotesh_divzero]
[    7.825391] lr : kotesh_divzero_probe+0x34/0x38 [kotesh_divzero]
[    7.834742] Call trace:
[    7.835107]  kotesh_divzero_probe+0x34/0x38 [kotesh_divzero]
[    7.835826]  platform_probe+0x70/0xf0
[    7.836253]  really_probe.part.0+0x94/0x310
...
[    7.846580] Code: 52800c81 b0000000 91008000 95fe8c21 (d4207d00)
[    7.848279] ---[ end trace c6db28d007078067 ]---
[    7.849695] note: udevd[119] exited with preempt_count 1
```

---

## 🔍 Panic Type
**Divide by Zero** — integer division by zero in kernel code.

On **ARM64**, there is no hardware divide-by-zero exception like x86.
Instead the compiler inserts a `BRK` (breakpoint) instruction before the
division. If the divisor is zero at runtime, the BRK fires and the kernel
reports `Unexpected kernel BRK exception at EL1`.

---

## 🔎 How to Read This Panic

### 1. Key Signature — ARM64 specific
```
Unexpected kernel BRK exception at EL1
Internal error: BRK handler: 00000000f20003e8 [#1]
```
- `BRK exception` → ARM64 breakpoint exception — NOT a CPU divide fault
- `f20003e8` → BRK immediate value used by compiler for divide-by-zero check
- `EL1` → Exception Level 1 = kernel mode (EL0 = user mode)
- On **x86** this would show: `divide error: 0000 [#1]` — different signature!

### 2. PC — Exact crash location
```
pc : kotesh_divzero_probe+0x34/0x38 [kotesh_divzero]
```
- Crashed inside `kotesh_divzero_probe`
- Offset `+0x34` of `0x38` total — near end of function
- Function is only 56 bytes total — very small function

### 3. Faulting Instruction
```
Code: 52800c81 b0000000 91008000 95fe8c21 (d4207d00)
```
- `(d4207d00)` = faulting instruction in parentheses
- `d4207d00` = ARM64 `BRK #0x3e80` instruction
- This is the compiler-inserted divide-by-zero check!

### 4. ARM64 vs x86 Divide by Zero

| Architecture | Mechanism | Panic Signature |
|---|---|---|
| ARM64 | Compiler inserts `BRK` before divide | `Unexpected kernel BRK exception` |
| x86 | CPU raises #DE exception | `divide error: 0000 [#1]` |

ARM64 has no hardware divide-by-zero trap — GCC inserts:
```asm
cbz  x1, .div_by_zero_trap   /* check if divisor == 0 */
udiv x0, x0, x1              /* actual division */
b    .continue
.div_by_zero_trap:
brk  #0x3e80                 /* BRK if divisor was 0 */
```

---

## 🔍 Root Cause

```c
static int kotesh_divzero_probe(struct platform_device *pdev)
{
    int a = 100;
    int b = 0;      /* divisor is zero! */
    int result;

    result = a / b; /* CRASH HERE — BRK fires */
    return 0;
}
```

The compiler detected the potential divide-by-zero at compile time and
inserted a runtime check. When `b == 0` at runtime, the BRK instruction
fires before the division even executes.

---

## ✅ Fix

Always validate divisor before dividing:

```c
static int kotesh_divzero_probe(struct platform_device *pdev)
{
    int a = 100;
    int b = 0;
    int result;

    /* Always check divisor before dividing */
    if (b == 0) {
        dev_err(&pdev->dev, "divisor is zero — cannot divide!\n");
        return -EINVAL;
    }

    result = a / b;
    pr_info("KOTESH_DIVZERO: result=%d\n", result);
    return 0;
}
```

For real driver scenarios:
```c
/* Common real-world examples */

/* Dividing by a register value */
if (clock_rate == 0) {
    dev_err(dev, "clock rate is zero!\n");
    return -EINVAL;
}
divisor = ref_clock / clock_rate;

/* Dividing by a DT property */
if (num_channels == 0) {
    dev_err(dev, "num-channels cannot be zero\n");
    return -EINVAL;
}
buf_size = total_size / num_channels;
```

---

## 🧠 Interview Explanation

> On ARM64, integer divide by zero does not trigger a hardware CPU exception like on x86. Instead, the GCC compiler inserts a runtime check before each division — if the divisor is zero, a `BRK` (breakpoint) instruction fires. The kernel reports this as "Unexpected kernel BRK exception at EL1" with BRK handler code `f20003e8`. This is different from x86 which shows "divide error: 0000". The faulting instruction in the Code line will be `d4207d00` which is `BRK #0x3e80`. The PC line shows exactly which function and offset caused it. The fix is to always validate that the divisor is non-zero before performing integer division, especially when the divisor comes from hardware registers, DT properties, or user-provided values.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_divzero.c` |
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
| `Unexpected kernel BRK exception at EL1` | ARM64 divide by zero |
| `BRK handler: 00000000f20003e8` | BRK immediate = divide-by-zero trap |
| `(d4207d00)` in Code line | ARM64 `BRK #0x3e80` instruction |
| `pc : func+offset` | Exact divide location |
| `note: udevd[X] exited with preempt_count 1` | Thread died with lock held |

---

## 📌 Full Panic Comparison So Far

| # | Panic Type | Key Signature | Fatal? |
|---|---|---|---|
| 01 | NULL Pointer | `Unable to handle kernel NULL pointer dereference` | Oops |
| 02 | Stack Overflow | `kernel stack overflow` + `Insufficient stack space` | Always |
| 03 | WARN_ON | `cut here` + `WARNING:` | ❌ No |
| 03 | BUG_ON | `kernel BUG at file:line` | ✅ Yes |
| 04 | Divide by Zero | `Unexpected kernel BRK exception at EL1` | ✅ Yes |

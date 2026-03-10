# Panic Issue 02 — Stack Overflow (Infinite Recursion)

---

## 📋 Category
`03_Panic_Analysis`

## 🔴 Panic Message

```
[    6.034018] KOTESH_STACK: probe called
[    6.034276] KOTESH_STACK: starting infinite recursion...
[    6.034653] KOTESH_STACK: depth=0
[    6.034941] KOTESH_STACK: depth=1
...
[    6.049390] KOTESH_STACK: depth=9
[    6.050684] Insufficient stack space to handle exception!
[    6.050945] ESR: 0x0000000096000047 -- DABT (current EL)
[    6.050985] FAR: 0xffffffc00978ffe0
[    6.051009] Task stack:     [0xffffffc009790000..0xffffffc009794000]
[    6.051020] Overflow stack: [0xffffff803fdc42c0..0xffffff803fdc52c0]
[    6.051504] pc : ___ratelimit+0x4/0x160
[    6.051608] lr : infinite_recurse+0x3c/0x190 [kotesh_stack_overflow]
[    6.051029] sp : ffffffc009790020
[    6.052546] Kernel panic - not syncing: kernel stack overflow
[    6.061642] ---[ end Kernel panic - not syncing: kernel stack overflow ]---
```

---

## 🔍 Panic Type
**Kernel Stack Overflow** — infinite recursion exhausted the kernel thread stack (16KB on ARM64)

---

## 🔎 How to Read This Panic

### 1. Key Signature Line
```
Insufficient stack space to handle exception!
```
This is ARM64's stack overflow detection. The kernel detected the stack
pointer crossed the stack guard page before the exception could be handled.

### 2. Stack Layout
```
Task stack:     [0xffffffc009790000..0xffffffc009794000]  ← 16KB kernel stack
Overflow stack: [0xffffff803fdc42c0..0xffffff803fdc52c0]  ← emergency overflow stack
sp : ffffffc009790020   ← stack pointer nearly at BOTTOM of task stack!
```
Stack grows **downward** on ARM64:
- Stack top    = `0xffffffc009794000`
- Stack bottom = `0xffffffc009790000`
- SP = `0xffffffc009790020` → only 32 bytes left from bottom → OVERFLOW!

### 3. FAR — Fault Address Register
```
FAR: 0xffffffc00978ffe0
```
FAR is the address that caused the fault. It is just **below** the stack bottom
(`0xffffffc009790000`), confirming the stack pointer went past the limit.

### 4. PC and LR — Where it crashed
```
pc : ___ratelimit+0x4/0x160
lr : infinite_recurse+0x3c/0x190 [kotesh_stack_overflow]
```
- `lr` shows we were inside `infinite_recurse` when the stack ran out
- `pc` shows we were about to call `___ratelimit` (for `pr_info_ratelimited`)
- Each call to `infinite_recurse` pushed a stack frame — eventually stack full

### 5. Final Panic
```
Kernel panic - not syncing: kernel stack overflow
```
Unlike NULL pointer dereference which produces an Oops, stack overflow
always produces a **hard panic** — system halts immediately.

---

## 🔍 Root Cause

```c
/* No base case — recurses forever */
static void infinite_recurse(int depth)
{
    pr_info_ratelimited("KOTESH_STACK: depth=%d\n", depth);
    infinite_recurse(depth + 1);   /* calls itself endlessly */
}

static int kotesh_stack_probe(struct platform_device *pdev)
{
    infinite_recurse(0);   /* starts the recursion */
    return 0;
}
```

Each function call pushes a **stack frame** (saved registers, local variables,
return address) onto the kernel stack. The kernel stack is only **16KB** on
ARM64. With infinite recursion, the stack fills up in a few hundred calls and
overflows into the guard page, triggering the panic.

**Stack frame layout per call:**
```
[return address (lr)]
[frame pointer (x29)]
[saved registers]
[local variables]
← sp moves down with each call
```

---

## ✅ Fix

Always ensure recursive functions have a **base case** to terminate:

```c
/* FIXED — with depth limit */
static void safe_recurse(int depth, int max_depth)
{
    if (depth >= max_depth)   /* base case — stop recursion */
        return;

    pr_info("KOTESH_STACK: depth=%d\n", depth);
    safe_recurse(depth + 1, max_depth);
}

static int kotesh_stack_probe(struct platform_device *pdev)
{
    safe_recurse(0, 10);   /* max 10 levels — safe */
    return 0;
}
```

For deep traversal, prefer **iterative** approach over recursive:
```c
/* Better — iterative instead of recursive */
static void iterative_traverse(int count)
{
    int i;
    for (i = 0; i < count; i++)
        pr_info("KOTESH_STACK: step=%d\n", i);
}
```

---

## 🧠 Interview Explanation

> Kernel stack overflow occurs when a kernel thread exhausts its stack space, typically due to infinite or excessively deep recursion. On ARM64, the kernel stack is 16KB per thread. Each function call consumes stack space for saved registers, frame pointer, and local variables. When the stack pointer crosses the bottom of the stack into the guard page, the ARM64 hardware raises a Data Abort. The kernel detects this as "Insufficient stack space to handle exception" and panics with "kernel stack overflow". Unlike a NULL pointer dereference which may produce only an Oops, stack overflow always causes a hard panic with no recovery. The stack layout in the panic message shows the task stack range and the SP value — if SP is near the bottom of the task stack range, it confirms overflow. The fix is to always have a base case in recursive functions or convert deep recursion to iteration.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_stack_overflow.c` |
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
| `Insufficient stack space to handle exception` | Stack overflow detected |
| `Kernel panic - not syncing: kernel stack overflow` | Hard panic — no recovery |
| `Task stack: [bottom..top]` | Kernel thread stack range (16KB) |
| `sp : ffffffc009790020` | SP near bottom of stack = overflow |
| `FAR: 0xffffffc00978ffe0` | Fault address — just below stack bottom |
| `lr : infinite_recurse+0x3c` | Last function called before overflow |
| `Overflow stack` | Emergency stack used to report the panic |

---

## 📌 Comparison — NULL Ptr vs Stack Overflow

| | Panic Issue 01 — NULL Ptr | Panic Issue 02 — Stack Overflow |
|---|---|---|
| Panic message | `Unable to handle kernel NULL pointer dereference` | `kernel stack overflow` |
| Always hard panic? | ❌ Oops (may survive) | ✅ Always hard panic |
| Key indicator | `virtual address 0000000000000000` | `Insufficient stack space` |
| SP location | Anywhere | Near bottom of task stack range |
| Call trace | Short — shows crash location | LR shows last recursive call |
| Fix | Validate pointer before use | Add base case or use iteration |

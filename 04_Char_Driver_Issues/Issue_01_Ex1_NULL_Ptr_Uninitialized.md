# Ch01 Exercise 1 – NULL Pointer: Uninitialized Struct Pointer

---

## 📋 Category
`04_Char_Driver_Issues`

## 🔴 Symptom

Module load kills the insmod process immediately. Kernel Oops captured in dmesg — NULL pointer dereference at address 0x0 inside `my_init()`:

```bash
kotesh@kotesh-ThinkPad-T460s:~/30days_workWith_BSP/my_projects/ch01_null_pointer$ sudo insmod sensor_driver_null_buggy.ko
Killed
```

```
[58449.720223] BUG: kernel NULL pointer dereference, address: 0000000000000000
[58449.720231] #PF: supervisor write access in kernel mode
[58449.720235] #PF: error_code(0x0002) - not-present page
[58449.720243] Oops: 0002 [#1] SMP PTI
[58449.720247] CPU: 3 PID: 575092 Comm: insmod Tainted: P OE 5.15.0-164-generic #174-Ubuntu
[58449.720255] RIP: 0010:my_init+0x16/0x1000 [sensor_driver_null_buggy]
[58449.720304] CR2: ffffffffc1ae1fec
[58449.720223] ---[ end trace 9cf3641104f1578a ]---
```

---

## 🔍 Stage Identification

Driver lifecycle stages:

1. `module_init()` called
2. Memory allocated (`kmalloc`)
3. Pointer used (`dev->value`)
4. Hardware initialized (hrtimer)
5. Driver ready

Failure occurred at:

👉 **Stage 3 — pointer used before Stage 2 (allocation) happened**

`dev` was never allocated. Kernel tried to write to address `0x0` → MMU page fault → Oops.

---

## 🔎 What I Checked

```bash
# 1. Load buggy module — killed immediately
sudo insmod sensor_driver_null_buggy.ko
# Killed

# 2. Check BUG line — confirms NULL address
dmesg | grep "BUG\|NULL"
# [58449.720223] BUG: kernel NULL pointer dereference, address: 0000000000000000

# 3. Check fault type — supervisor write access
dmesg | grep "#PF"
# #PF: supervisor write access in kernel mode
# #PF: error_code(0x0002) - not-present page

# 4. Check exact crash location
dmesg | grep "RIP"
# RIP: 0010:my_init+0x16/0x1000 [sensor_driver_null_buggy]

# 5. Check full call trace
dmesg | grep -A10 "Call Trace"
# do_one_initcall → do_init_module → load_module → my_init → CRASH
```

✔ Confirmed `address: 0000000000000000` → pointer was NULL

✔ Confirmed `supervisor write access` → kernel tried to **write** to NULL

✔ Confirmed `error_code(0x0002)` → write fault, page not present

✔ Confirmed `RIP: my_init+0x16` → crash at offset 0x16 inside `my_init()`

✔ Confirmed `Oops: 0002` → x86 page fault code for write to non-present page

✔ System survived — `Tainted: P OE` — Oops but not full panic on this kernel

---

## 🔍 Root Cause

```c
/* BUGGY CODE — sensor_driver_null_buggy.c */

struct sensor_data {
    int value;
    int threshold;
};

static struct sensor_data *dev;   /* declared as global — value is NULL */

static int __init my_init(void)
{
    pr_info("Sensor Driver: Initializing...\n");

    dev->value = 0;               /* CRASH: writing to address 0x0 */
    dev->threshold = 100;         /* never reached */
}
```

The pointer `dev` is declared as a global but **never allocated**.
In C, uninitialized global pointers are `NULL` (0x0).
Writing to address `0x0` → MMU raises page fault → kernel Oops.

**x86 vs ARM64 difference:**

| Platform | NULL dereference result |
|---|---|
| x86 (this machine) | Oops — system may survive if in user context |
| ARM64 (QEMU) | `Unable to handle kernel NULL pointer dereference` — usually fatal |
| User space (any) | SIGSEGV — only process dies, system fine |

**Why `insmod` was `Killed`:**
The kernel Oops occurred inside `do_init_module()` called by the `insmod` syscall.
The kernel killed the calling process (`insmod`) as part of Oops handling.

---

## ✅ Fix

→ See Exercise 2 — fix using `kmalloc` + NULL check + `kfree`

```c
/* FIXED */
dev = kmalloc(sizeof(*dev), GFP_KERNEL);
if (!dev)
    return -ENOMEM;

dev->value = 0;        /* safe — memory allocated */
dev->threshold = 100;
```

---

## 🧠 Interview Explanation

The kernel module declared a struct pointer as a global variable but never allocated memory for it. In C, uninitialized global pointers default to NULL (0x0). When `my_init()` tried to write to `dev->value`, the CPU raised a page fault at address 0x0. Unlike user space where only the process gets SIGSEGV, in kernel space there is no higher authority to catch the fault — the kernel generates an Oops and kills the faulting context. The fix is to always allocate memory with `kmalloc` before using a pointer, and always check the return value for NULL.

---

## 📁 Related Files

| File | Path |
|---|---|
| Buggy driver | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/sensor_driver_null_buggy.c` |
| Fixed driver | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/sensor_driver_null_fixed.c` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Step 1 — Build
cd ~/30days_workWith_BSP/my_projects/ch01_null_pointer
make

# Step 2 — Load buggy module
sudo insmod sensor_driver_null_buggy.ko
# Expected: Killed

# Step 3 — Capture crash
dmesg | grep -B2 -A20 "BUG: kernel NULL"

# Step 4 — Decode crash offset to source line
objdump -d sensor_driver_null_buggy.o | grep -A10 "<my_init>"
# offset +0x16 = the dev->value = 0 line
```

---

## ✅ Key Diagnostic Commands

```bash
# Confirm NULL address
dmesg | grep "BUG: kernel NULL"

# Confirm write fault
dmesg | grep "#PF"

# Find exact crash location in function
dmesg | grep "RIP:"

# Full call trace
dmesg | grep -A15 "Call Trace"

# Decode offset to source line
objdump -d <module>.o | grep -A20 "<function_name>"
```

---

## 📌 Key Learning

- Global pointers in C are `NULL` by default — always allocate before use
- `#PF: supervisor write access` → kernel tried to **write** to bad address
- `error_code(0x0002)` → write fault to non-present page (x86 specific)
- `RIP: function+offset` → exact location of crash inside function
- On x86 the system may survive a NULL deref Oops — on ARM64 it is usually fatal
- `insmod` process gets `Killed` when Oops occurs during module init
- Use `objdump -d` to decode `+0x16` offset to exact source line

---

*Kotesh S — BSP Lab — Ch01 Exercise 1 — March 2026*

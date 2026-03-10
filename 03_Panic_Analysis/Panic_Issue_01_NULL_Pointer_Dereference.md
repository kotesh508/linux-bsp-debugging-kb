# Panic Issue 01 — NULL Pointer Dereference

---

## 📋 Category
`03_Panic_Analysis`

## 🔴 Panic Message

```
[    7.434649] KOTESH_NULL: probe called
[    7.435084] KOTESH_NULL: about to dereference NULL pointer...
[    7.448946] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
[    7.449781] Mem abort info:
[    7.450043]   ESR = 0x0000000096000045
[    7.450458]   EC = 0x25: DABT (current EL), IL = 32 bits
[    7.483041] Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
[    7.488534] pc : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
[    7.490629] lr : kotesh_null_probe+0x2c/0x54 [kotesh_null_ptr]
[    7.499868] Call trace:
[    7.500255]  kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
[    7.500925]  platform_probe+0x70/0xf0
[    7.501329]  really_probe.part.0+0x94/0x310
[    7.501755]  __driver_probe_device+0xa0/0x180
[    7.502175]  driver_probe_device+0x4c/0x130
[    7.502582]  __driver_attach+0x9c/0x1a0
[    7.502992]  bus_for_each_dev+0x7c/0xe0
[    7.503379]  driver_attach+0x2c/0x40
[    7.503737]  bus_add_driver+0x114/0x210
[    7.504116]  driver_register+0x80/0x140
[    7.504503]  __platform_driver_register+0x2c/0x40
[    7.504958]  kotesh_null_driver_init+0x28/0x1000 [kotesh_null_ptr]
[    7.505606]  do_one_initcall+0x68/0x2c0
[    7.510613] Code: 91008000 95fe9823 d2800000 52800541 (b9000001)
[    7.511955] ---[ end trace 5ff1560436b66bf5 ]---
[    7.654108] udevd[111]: worker [116] terminated by signal 11 (Segmentation fault)
```

---

## 🔍 Panic Type
**NULL Pointer Dereference** — driver attempted to write to virtual address `0x0000000000000000`

---

## 🔎 How to Read This Panic

### 1. First Line — What happened
```
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
```
- `virtual address 0000000000000000` → address is NULL (0x0)
- Kernel tried to access address 0 which is never mapped

### 2. ESR — Exception Syndrome Register
```
ESR = 0x0000000096000045
EC  = 0x25: DABT (current EL)   → Data Abort at current Exception Level
WnR = 1                          → Write operation (not read)
FSC = 0x05: level 1 translation fault → page not mapped
```

### 3. PC and LR — Where it crashed
```
pc : kotesh_null_probe+0x34/0x54 [kotesh_null_ptr]
lr : kotesh_null_probe+0x2c/0x54 [kotesh_null_ptr]
```
- `pc` = Program Counter = exact instruction that crashed
- `kotesh_null_probe` = function name
- `+0x34` = offset within function (34 bytes in)
- `/0x54` = total function size (84 bytes)
- `[kotesh_null_ptr]` = module name

### 4. Register Dump — Key register
```
x0 : 0000000000000000   ← NULL pointer stored in x0
x1 : 000000000000002a   ← value 42 (0x2a) we tried to write
```
`x0 = 0` confirms ptr was NULL when we did `*ptr = 42`

### 5. Call Trace — How we got here
```
kotesh_null_probe+0x34           ← our driver probe (crash here)
platform_probe+0x70              ← platform bus called probe
really_probe.part.0+0x94        ← kernel probe infrastructure
__driver_probe_device+0xa0      ← driver-device match triggered probe
driver_probe_device+0x4c
__driver_attach+0x9c
bus_for_each_dev+0x7c
driver_attach+0x2c
bus_add_driver+0x114
driver_register+0x80
__platform_driver_register+0x2c
kotesh_null_driver_init+0x28    ← module_init called
do_one_initcall+0x68            ← kernel called module init
do_init_module+0x50
load_module+0x2240              ← module was loaded (insmod/autoload)
__do_sys_finit_module+0xa8
```
**Read bottom-up:** module loaded → init called → driver registered →
probe triggered → crash in probe.

### 6. Code Line — Faulting instruction
```
Code: 91008000 95fe9823 d2800000 52800541 (b9000001)
```
- `(b9000001)` = faulting instruction in parentheses
- `b9000001` = ARM64 `STR W1, [X0]` = store word at address in X0
- X0 was NULL → fault

---

## 🔍 Root Cause

```c
static int kotesh_null_probe(struct platform_device *pdev)
{
    int *ptr = NULL;           /* ptr initialized to NULL */

    pr_info("KOTESH_NULL: about to dereference NULL pointer...\n");

    *ptr = 42;                 /* CRASH HERE — write to address 0 */
    return 0;
}
```

Writing to a NULL pointer dereferences virtual address 0x0 which is never
mapped in the kernel page tables. The MMU raises a Data Abort exception.

---

## ✅ Fix

Always validate pointers before dereferencing:

```c
static int kotesh_null_probe(struct platform_device *pdev)
{
    int *ptr = NULL;

    /* Validate before use */
    if (!ptr) {
        dev_err(&pdev->dev, "ptr is NULL — cannot dereference!\n");
        return -EINVAL;
    }

    *ptr = 42;
    return 0;
}
```

For real drivers, common NULL pointer sources:
```c
/* devm_* functions return NULL or ERR_PTR on failure */
priv = devm_kzalloc(&pdev->dev, sizeof(*priv), GFP_KERNEL);
if (!priv)
    return -ENOMEM;

/* platform_get_resource returns NULL if property missing */
res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
if (!res)
    return -EINVAL;
```

---

## 🧠 Interview Explanation

> A NULL pointer dereference occurs when kernel code tries to read or write through a pointer that is NULL (address 0x0). In Linux on ARM64, virtual address 0 is never mapped, so the MMU raises a Data Abort exception which the kernel reports as "Unable to handle kernel NULL pointer dereference". The panic message shows the faulting PC (exact function and offset), the call trace (how execution reached that point), and the register dump (which register held NULL). The key fields to read are: the virtual address (confirms NULL), the PC line (identifies the exact function), and the call trace (shows the execution path). The fix is always to validate pointers before use and return an appropriate error code if they are NULL.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_null_ptr.c` |
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
| `Unable to handle kernel NULL pointer dereference` | Access to address 0x0 |
| `virtual address 0000000000000000` | Confirms NULL (address = 0) |
| `EC = 0x25: DABT` | Data Abort — memory access fault |
| `WnR = 1` | Write operation caused the fault |
| `pc : func+offset/size [module]` | Exact crash location |
| `lr : func+offset/size [module]` | Caller of crashed function |
| `Call trace` | Execution path — read bottom-up |
| `(b9000001)` | Faulting ARM64 instruction |
| `x0 = 0000...0000` | Register holding NULL pointer |

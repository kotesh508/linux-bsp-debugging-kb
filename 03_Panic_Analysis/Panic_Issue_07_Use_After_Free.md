# Panic Issue 07 — Use After Free (UAF)

---

## 📋 Category
`03_Panic_Analysis`

---

## 🔴 Symptom Output

```
[    5.304793] KOTESH_UAF: probe called
[    5.305203] KOTESH_UAF: allocated data at ffffff8002e98c00, value=42
[    5.305751] KOTESH_UAF: freed data
[    5.318735] KOTESH_UAF: accessing freed memory...
[    5.319205] KOTESH_UAF: data->value = 0        ← was 42, now 0 — stale/corrupted!
[    5.319515] KOTESH_UAF: wrote to freed memory — value now 99   ← silent write!

qemuarm64 login: root          ← SYSTEM SURVIVED — no crash, no warning!
root@qemuarm64:~# echo "survived?"
survived?
```

**Key observation:** No Oops, no panic, no KASAN report. The kernel silently
allowed both the read and write to freed memory. This is the most dangerous
class of kernel bug — the corruption is invisible without special tooling.

---

## 🔍 Panic Type
**Use After Free (UAF)** — accessing (reading or writing) memory that has
already been freed back to the kernel heap allocator (SLUB/SLAB). Without KASAN
enabled this is **completely silent** — the system may keep running with
corrupted state.

---

## 🔎 What Happened Step by Step

```c
/* Step 1: allocate */
data = kmalloc(sizeof(*data), GFP_KERNEL);
data->value = 42;
// Memory at ffffff8002e98c00: [value=42, name="..."]

/* Step 2: free */
kfree(data);
// Memory returned to SLUB free list
// SLUB may have overwritten it with free-list metadata
// data->value is now 0 (SLUB zeroed/poisoned it)

/* Step 3: UAF READ — reads stale/corrupted data */
pr_info("data->value = %d\n", data->value);
// Prints 0 — not 42! Memory was modified by SLUB after free

/* Step 4: UAF WRITE — silently corrupts heap */
data->value = 99;
// Overwrites whatever SLUB put there — could corrupt another object
// that was allocated at the same address
```

### Why `value` changed from 42 to 0:
After `kfree()`, SLUB writes its own metadata (free-list pointer) into the
freed chunk. This overwrites the `value` field. The 0 we read back is actually
SLUB's internal bookkeeping data, not our original value.

### Why the write didn't crash:
The address `ffffff8002e98c00` is still valid kernel memory — it's just back in
the SLUB free pool. Writing to it succeeds silently. If SLUB had reallocated
that chunk to another object between the `kfree()` and the UAF write, we would
have corrupted a live kernel object.

---

## 🔎 Three UAF Outcomes (by timing)

| Scenario | What happens | Detectable? |
|---|---|---|
| UAF before reallocation | Reads/writes stale SLUB metadata | Only with KASAN |
| UAF after reallocation | Corrupts another live object → eventual Oops | Much later, wrong location |
| UAF with KASAN enabled | Immediate `BUG: KASAN: use-after-free` report | ✅ Yes, immediately |

Our case = first scenario. The memory hadn't been reallocated yet.

---

## 🔎 Why UAF is the Most Dangerous Kernel Bug

1. **Silent** — no crash at the point of the bug
2. **Delayed** — crash may happen much later in unrelated code
3. **Non-deterministic** — depends on heap allocator timing
4. **Security exploit** — attacker can control what gets allocated at the freed
   address, then trigger the UAF write to corrupt that object (type confusion)
5. **Hard to debug** — crash location has no relation to the actual bug

---

## 🔎 KASAN — The Right Tool to Detect UAF

**KASAN (Kernel Address SANitizer)** instruments every memory access and
detects UAF immediately. Without KASAN our UAF was silent. With KASAN enabled
the output would be:

```
==================================================================
BUG: KASAN: use-after-free in kotesh_uaf_probe+0x.../0x...
Write of size 4 at addr ffffff8002e98c00 by task udevd/115

CPU: 0 PID: 115 Comm: udevd
Call trace:
 kotesh_uaf_probe+0x.../0x... [kotesh_uaf]
 platform_probe+0x70/0xf0
 ...

Allocated by task 115:
 kmalloc+0x.../0x...
 kotesh_uaf_probe+0x.../0x... [kotesh_uaf]

Freed by task 115:
 kfree+0x.../0x...
 kotesh_uaf_probe+0x.../0x... [kotesh_uaf]
==================================================================
```

KASAN shows: what was accessed, where it was allocated, and where it was freed.

### Enable KASAN in Yocto kernel config:
```
CONFIG_KASAN=y
CONFIG_KASAN_GENERIC=y
CONFIG_KASAN_INLINE=y
```

Add to `meta-kotesh/recipes-kernel/linux/linux-yocto_%.bbappend`:
```bitbake
KERNEL_EXTRA_FEATURES += "features/kasan/kasan.scc"
```

---

## 🔎 SLUB Debugging — Lightweight Alternative to KASAN

Without KASAN, SLUB debug mode can help catch UAF:

```bash
# Boot with SLUB debug poison enabled
# Add to kernel cmdline:
slub_debug=P   # poison freed memory with 0x6b pattern

# With poison enabled, UAF read returns 0x6b6b6b6b instead of real data
# UAF write to poisoned page may cause Oops
```

Add to QEMU `-append`:
```
-append "console=ttyAMA0 root=/dev/vda rw slub_debug=P"
```

With poison enabled, our UAF read would return `0x6b6b6b6b` (1802201963)
instead of 0, making the bug more visible.

---

## ✅ Fix

### Wrong — UAF pattern:
```c
data = kmalloc(sizeof(*data), GFP_KERNEL);
data->value = 42;
kfree(data);
data->value = 99;   /* BUG: UAF! */
```

### Correct — NULL after free:
```c
data = kmalloc(sizeof(*data), GFP_KERNEL);
data->value = 42;
kfree(data);
data = NULL;        /* always NULL after free */

/* Now any access causes immediate NULL ptr Oops — visible and debuggable */
if (data)
    data->value = 99;   /* safe — never reached */
```

### Best practice — use devm_ allocations in drivers:
```c
/* devm_ allocations are automatically freed when device is removed */
/* No manual kfree needed — no UAF possible */
data = devm_kmalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
if (!data)
    return -ENOMEM;
/* No kfree — kernel handles cleanup */
```

---

## 🧠 Interview Explanation

> Use-After-Free is one of the most dangerous kernel bugs because it causes
> silent memory corruption without any immediate crash. After `kfree()`, the
> SLUB allocator reclaims the memory and may overwrite it with its own metadata
> or reallocate it to another object. If the original pointer is accessed again,
> reads return corrupted data and writes silently corrupt the heap — potentially
> corrupting a completely different kernel object. The bug may not manifest as
> a crash until much later in unrelated code, making it extremely hard to debug.
> The correct tool is KASAN (Kernel Address Sanitizer), which instruments every
> memory access and immediately reports UAF with full allocation and free
> backtraces. In BSP driver development, the best prevention is using `devm_`
> allocations which are automatically managed, and always setting pointers to
> NULL after `kfree()` so any subsequent access causes an immediate visible
> NULL pointer Oops rather than silent corruption.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_uaf.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/kotesh-panic-driver.bb` |

---

## 🧪 How to Reproduce

```bash
# 1. Boot with kotesh-uaf DTS node enabled
# 2. Check dmesg:
dmesg | grep KOTESH_UAF

# Expected output — silent UAF:
# KOTESH_UAF: allocated data at <addr>, value=42
# KOTESH_UAF: freed data
# KOTESH_UAF: accessing freed memory...
# KOTESH_UAF: data->value = 0    ← corrupted, was 42
# KOTESH_UAF: wrote to freed memory — value now 99

# 3. To make visible — boot with SLUB poison:
# Add slub_debug=P to kernel cmdline
```

---

## ✅ Key Diagnostic Commands

```bash
# Check if KASAN is enabled
zcat /proc/config.gz | grep KASAN

# Check SLUB debug state
cat /sys/kernel/slab/<slab_name>/poison

# Enable SLUB debug at boot
# Add to kernel cmdline: slub_debug=FPZU

# Check for memory corruption markers
dmesg | grep -i "kasan\|use-after-free\|heap"
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
| 06 | Oops → Panic | `Kernel panic - not syncing: sysrq triggered crash` | Depends on `panic_on_oops` |
| 07 | Use After Free | Silent — no signature without KASAN | ❌ Silent corruption |

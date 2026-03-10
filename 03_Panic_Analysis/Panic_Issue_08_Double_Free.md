# Panic Issue 08 — Double Free

---

## 📋 Category
`03_Panic_Analysis`

---

## 🔴 Symptom Output

```
[    5.xxx] KOTESH_DFREE: probe called
[    5.xxx] KOTESH_DFREE: allocated at ffffff8002e98c00, value=42
[    5.xxx] KOTESH_DFREE: first kfree — OK
[    5.xxx] KOTESH_DFREE: about to double free...

[    6.xxx] Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
[    6.xxx] Internal error: Oops: 0000000096000045 [#2] PREEMPT SMP
[    6.xxx] Internal error: Oops: 0000000096000045 [#3] PREEMPT SMP
...
[    6.xxx] Internal error: Oops: 0000000096000045 [#5] PREEMPT SMP
...
[    9.038] Internal error: Oops: 0000000096000045 [#9] PREEMPT SMP
[    9.056] WARNING: CPU: 0 PID: 81 at kernel/exit.c:788
[    9.xxx] Fixing recursive fault but reboot is needed!
```

**Key observation:** The double free triggered a **cascade of 9 Oops** across
multiple unrelated kernel threads (udevd workers, jbd2 filesystem journal).
The corruption spread from the SLUB heap to the page allocator and eventually
corrupted the EXT4 journal thread.

---

## 🔎 The Smoking Gun — SLUB Poison Magic Value

```
x4 : dead000000000100   ← THIS IS THE KEY
```

`dead000000000100` is **SLUB's LIST_POISON2** value. SLUB writes this magic
value into freed objects' next pointer to detect double frees and use-after-free.
When we see this in a register during a crash it means:

- The code tried to dereference a pointer that SLUB had poisoned
- This is **direct evidence of heap corruption** from double free or UAF
- SLUB uses two poison values: `dead000000000100` (LIST_POISON2) and
  `dead000000000200` (LIST_POISON1)

---

## 🔎 What Happened Step by Step

```
Step 1: kmalloc() → chunk at ffffff8002e98c00 allocated
        SLUB marks it as "in use"

Step 2: kfree() #1 → chunk returned to SLUB free list
        SLUB writes dead000000000100 into chunk's next pointer
        SLUB marks it as "free"

Step 3: kfree() #2 → SAME chunk freed again
        SLUB tries to add it to free list AGAIN
        Writes dead000000000100 into already-poisoned memory
        Free list is now CORRUPT — a chunk appears twice in the list

Step 4: Next kmalloc() somewhere else gets the corrupted chunk
        SLUB reads next pointer → gets dead000000000100 as an address
        Tries to dereference 0x...0008 → NULL pointer fault → Oops #1

Step 5: Oops handler tries to clean up → needs to allocate memory
        Gets another corrupted chunk → Oops #2
        Recursive! → Oops #3, #4, #5...

Step 6: Eventually corrupts jbd2 (EXT4 journal) kernel thread
        jbd2/vda-8 tries to allocate bio → gets corrupted memory → Oops #9
        "Fixing recursive fault but reboot is needed!"
```

---

## 🔎 Crash Address Analysis

```
[0000000000000008] pgd=0000000000000000
pc : get_page_from_freelist+0x1d8/0xe40
```

Address `0x0000000000000008` = NULL + 8 bytes offset. This means the code
tried to access field at offset 8 of a NULL pointer. The NULL came from
dereferencing `dead000000000100` which SLUB had placed in the corrupted chunk —
the CPU read 0 from that poisoned location and then tried to use it as a pointer.

---

## 🔎 Oops Counter — [#N] Significance

```
[#1] PREEMPT SMP   ← first Oops
[#2] PREEMPT SMP   ← second Oops — kernel now tainted D
[#5] PREEMPT SMP   ← fifth Oops
[#9] PREEMPT SMP   ← ninth Oops — filesystem journal corrupted
```

The `[#N]` counter tracks how many Oops have occurred since boot. When `N > 1`
it means:

- Previous Oops didn't kill the system (no `panic_on_oops`)
- Each new Oops is a **consequence** of earlier heap corruption
- The kernel is in a progressively more corrupted state
- `Tainted: G D` = kernel is DYING — `D` flag set after first Oops

The crash location (`get_page_from_freelist`) is completely unrelated to the
actual double free — this is the **hallmark of heap corruption**: the bug is
in one place, the crash is somewhere completely different.

---

## 🔎 Double Free vs UAF — Comparison

| Property | Use After Free | Double Free |
|---|---|---|
| Operation | access after kfree | kfree twice |
| Immediate crash? | No — silent | Sometimes — if SLUB detects it |
| Detection | KASAN only | SLUB poison + KASAN |
| Cascade? | Rare | Yes — corrupts free list |
| Magic value | N/A | `dead000000000100` in registers |
| Crash location | Near UAF site | Anywhere — random allocation |
| Severity | High | Critical — filesystem corruption |

---

## 🔎 SLUB Poison Magic Values

| Value | Name | Meaning |
|---|---|---|
| `0x6b6b6b6b6b6b6b6b` | POISON_FREE | Memory has been freed (debug mode) |
| `0x5a5a5a5a5a5a5a5a` | POISON_INUSE | Memory is allocated (debug mode) |
| `dead000000000100` | LIST_POISON2 | SLUB free list next pointer |
| `dead000000000200` | LIST_POISON1 | SLUB free list prev pointer |
| `dead000000000400` | LIST_POISON3 | Used in other list operations |

Seeing any of these in a crash register dump = **immediate heap corruption flag**.

---

## 🔎 How SLUB Detects Double Free (with slub_debug)

With `slub_debug=FZ` boot parameter SLUB can catch double free immediately:

```
=============================================================================
BUG kmalloc-64 (Tainted: G    B   ): Object already free
-----------------------------------------------------------------------------

INFO: Allocated in kotesh_doublefree_probe+0x... age=3 cpu=0 pid=115
INFO: Freed in kotesh_doublefree_probe+0x... age=2 cpu=0 pid=115
INFO: Freed in kotesh_doublefree_probe+0x... age=1 cpu=0 pid=115  ← double!

Call trace for double free:
 kfree+0x.../0x...
 kotesh_doublefree_probe+0x.../0x...
```

---

## ✅ Fix

### Wrong — double free:
```c
data = kmalloc(sizeof(*data), GFP_KERNEL);
kfree(data);   /* first free — OK */
kfree(data);   /* BUG: double free! */
```

### Correct — NULL after free:
```c
data = kmalloc(sizeof(*data), GFP_KERNEL);
kfree(data);
data = NULL;   /* NULL immediately after free */
kfree(data);   /* kfree(NULL) is always safe — no-op */
```

`kfree(NULL)` is **explicitly safe** in the Linux kernel — it checks for NULL
and returns immediately. Always set pointers to NULL after freeing.

### Best practice — use devm_ in drivers:
```c
/* devm_kmalloc is freed automatically on device remove */
/* No manual kfree needed — double free impossible */
data = devm_kmalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
```

### Error path pattern — common source of double free:
```c
static int probe(struct platform_device *pdev)
{
    data = kmalloc(...);

    ret = do_something();
    if (ret) {
        kfree(data);     /* free on error */
        return ret;
    }

    return 0;
}

static int remove(struct platform_device *pdev)
{
    kfree(data);         /* BUG: also freed in error path above! */
}
```

Fix: use `devm_kmalloc` or set `data = NULL` after error-path free.

---

## 🧠 Interview Explanation

> A double free occurs when `kfree()` is called twice on the same pointer.
> The first `kfree()` returns the chunk to SLUB's free list and writes the
> poison value `dead000000000100` into it. The second `kfree()` corrupts the
> free list by inserting the same chunk twice. Subsequent allocations anywhere
> in the kernel may receive the corrupted chunk, and when the kernel tries to
> follow its next pointer it gets `dead000000000100` as an address, causing a
> NULL dereference at offset 0x8. This triggers a cascade of Oops across
> completely unrelated kernel threads — in our case corrupting 9 different
> contexts including the EXT4 journal thread. The crash location has no
> relation to the actual double free bug. The smoking gun in the register dump
> is `x4: dead000000000100` — SLUB's LIST_POISON2 magic value. The fix is to
> always set pointers to NULL after `kfree()` since `kfree(NULL)` is a safe
> no-op, or better yet use `devm_kmalloc()` for driver allocations which are
> managed automatically.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_doublefree.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/kotesh-panic-driver.bb` |

---

## ✅ Key Diagnostic Commands

```bash
# Enable SLUB debug to catch double free at point of occurrence
# Add to kernel cmdline:
slub_debug=FZ

# Check for SLUB BUG reports
dmesg | grep -i "BUG\|double free\|Object already free"

# Look for poison magic values in Oops register dumps
dmesg | grep "dead0000"

# Check if KASAN is available
zcat /proc/config.gz | grep KASAN

# Watch Oops counter escalating — sign of cascade
dmesg | grep "Internal error: Oops.*\[#"
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
| 07 | Use After Free | Silent — no signature without KASAN | ❌ Silent |
| 08 | Double Free | `dead000000000100` in registers + Oops cascade [#N] | ✅ Cascade |

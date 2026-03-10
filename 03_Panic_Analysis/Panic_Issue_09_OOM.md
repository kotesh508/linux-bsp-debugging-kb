# Panic Issue 09 — Out of Memory (OOM)

---

## 📋 Category
`03_Panic_Analysis`

---

## 🔴 Symptom Output

```
[    4.950909] KOTESH_OOM: probe called
[    4.951198] KOTESH_OOM: starting memory exhaustion — allocating 1MB chunks...
[    5.255074] KOTESH_OOM: allocated 100 MB so far...
[    5.492508] KOTESH_OOM: allocated 200 MB so far...
[    5.706127] KOTESH_OOM: allocated 300 MB so far...
[    5.798259] KOTESH_OOM: allocated 400 MB so far...
[    5.854500] KOTESH_OOM: allocated 500 MB so far...
[    5.914308] KOTESH_OOM: allocated 600 MB so far...
[    5.970952] KOTESH_OOM: allocated 700 MB so far...
[    6.028644] KOTESH_OOM: allocated 800 MB so far...
[    6.089846] KOTESH_OOM: allocated 900 MB so far...

[    6.142268] udevd: page allocation failure: order:8, mode:0x40cc0(GFP_KERNEL|__GFP_COMP)
               nodemask=(null),cpuset=/,mems_allowed=0

[    6.192237] KOTESH_OOM: kmalloc failed at iteration 945 (945 MB allocated)
[    6.192700] KOTESH_OOM: allocated total 945 MB — OOM should fire!
```

**Memory state at time of failure:**
```
MemTotal:    1009136 kB   (985 MB total)
MemFree:        6728 kB   (6 MB free!)
Slab:         987940 kB   (964 MB in slab — our allocations!)
SUnreclaim:   978300 kB   (955 MB unreclaimable slab)
Swap:              0 kB   (no swap configured)

free -m output:
Mem:   985   963   6   0   15   8
       ^^^   ^^^
       total used — 963 MB used out of 985 MB!
```

---

## 🔍 What Happened — Two OOM Behaviors

### What we observed: Page Allocation Failure (soft OOM)
```
udevd: page allocation failure: order:8, mode:0x40cc0(GFP_KERNEL|__GFP_COMP)
```
- `kmalloc(1MB)` requires **order:8** = 2^8 = 256 contiguous pages
- At 945MB allocated, no contiguous 256-page block exists anymore
- Kernel prints warning and returns NULL — **graceful failure**
- `kmalloc()` returned NULL → our driver detected it → stopped allocating
- System survived because kernel memory (slab) was freed when probe() returned

### What would happen with GFP_ATOMIC or harder pressure:
```
Out of memory: Killed process XXX (udevd) score YYY or YYY*
oom_reaper: reaped process XXX, now anon-rss:0kB, file-rss:0kB
```
- OOM killer fires when NO memory reclaim is possible
- Selects highest-scoring process (oom_score) to kill
- Kills it and reclaims its pages
- System may survive if enough memory recovered

---

## 🔎 Understanding the Page Allocation Failure

```
page allocation failure: order:8, mode:0x40cc0(GFP_KERNEL|__GFP_COMP)
```

| Field | Meaning |
|---|---|
| `order:8` | Requested 2^8 = 256 contiguous pages = 1MB |
| `GFP_KERNEL` | Normal kernel allocation, can sleep/wait |
| `__GFP_COMP` | Compound page (huge page) requested |
| `nodemask=(null)` | Single NUMA node system |

The kernel tried to find 256 **contiguous** free pages but couldn't — even
though ~8MB was technically free, it was fragmented. This is **memory
fragmentation** — total free memory exists but not in one contiguous block.

---

## 🔎 Memory State Analysis

```
Slab:         987940 kB  ← 964 MB in SLUB allocator
SUnreclaim:   978300 kB  ← 955 MB unreclaimable (our kmalloc chunks)
SReclaimable:   9640 kB  ← only 9 MB reclaimable
MemFree:        6728 kB  ← only 6 MB free
```

Our driver consumed **955 MB of unreclaimable slab memory**. The kernel could
not reclaim it because:
1. No swap configured (`SwapTotal: 0 kB`)
2. slab memory from `kmalloc()` is unreclaimable until explicitly freed
3. `GFP_KERNEL` can reclaim page cache but not unreclaimable slab

**Why system survived:**
- `probe()` returned after kmalloc failed
- The local `ptrs[]` array went out of scope
- But... the allocated chunks were NOT freed! They leaked until module unload
- System survived because probe() returned — udevd worker thread exited

---

## 🔎 OOM Killer — How It Works (full OOM scenario)

When all reclaim fails the OOM killer fires:

```
Out of memory: Kill process 115 (udevd) score 900 or sacrifice child
Killed process 115 (udevd) total-vm:12345kB, anon-rss:960000kB
oom_reaper: reaped process 115, now anon-rss:0kB, file-rss:0kB
```

### OOM Score Calculation:
```bash
# Check any process's OOM score
cat /proc/<pid>/oom_score

# Check OOM score adjustment
cat /proc/<pid>/oom_score_adj

# Protect a process from OOM killer (-1000 = never kill)
echo -1000 > /proc/<pid>/oom_score_adj

# Make a process preferred OOM target (+1000 = kill first)
echo 1000 > /proc/<pid>/oom_score_adj
```

### OOM killer selection algorithm:
- Highest `oom_score` = most memory used + adjustment
- Kernel prefers to kill processes with large RSS
- Never kills kernel threads or processes with `oom_score_adj = -1000`
- In embedded: `init` (PID 1) is protected by default

---

## 🔎 GFP Flags — Memory Allocation Modes

| Flag | Context | Behavior on low memory |
|---|---|---|
| `GFP_KERNEL` | Normal kernel code | Can sleep, reclaim, wait |
| `GFP_ATOMIC` | IRQ/softirq context | Cannot sleep — fails immediately |
| `GFP_NOWAIT` | Kernel, no wait | Returns NULL if not immediately available |
| `GFP_NOFS` | Filesystem code | Can't recurse into filesystem |
| `GFP_NOIO` | Block layer | Can't trigger I/O |
| `GFP_HIGHUSER` | Userspace pages | Normal user allocation |

**Key rule for BSP drivers:**
- Use `GFP_KERNEL` in probe/remove (process context — can sleep)
- Use `GFP_ATOMIC` in interrupt handlers (cannot sleep)
- Never use `GFP_KERNEL` in atomic/IRQ context — will BUG()

---

## 🔎 Memory Leak vs OOM

Our driver has a **memory leak**:
```c
for (i = 0; i < 2048; i++) {
    ptrs[i] = kmalloc(chunk, GFP_KERNEL);
    /* allocated but NEVER freed! */
}
```

The 945 MB stays allocated until the module is unloaded. In a real driver this
would cause gradual memory exhaustion over time — system runs fine for hours
then suddenly OOMs.

### Detecting memory leaks:
```bash
# Watch slab usage over time
watch -n1 'cat /proc/meminfo | grep -i slab'

# Check specific slab caches
cat /proc/slabinfo

# Use kmemleak (if CONFIG_DEBUG_KMEMLEAK=y)
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak
```

---

## 🔎 panic_on_oom — Production Embedded Setting

```bash
# Check current setting
cat /proc/sys/vm/panic_on_oom

# 0 = OOM killer fires (default)
# 1 = panic if OOM killer can't help
# 2 = always panic on OOM

# For safety-critical embedded systems:
echo 2 > /proc/sys/vm/panic_on_oom
```

Combined with watchdog for auto-reboot:
```bash
echo 2 > /proc/sys/vm/panic_on_oom
echo 5 > /proc/sys/kernel/panic_timeout
```

---

## ✅ Fix

### Wrong — allocate without freeing:
```c
for (i = 0; i < 2048; i++) {
    ptrs[i] = kmalloc(chunk, GFP_KERNEL);
    /* never freed — memory leak! */
}
```

### Correct — always free on error and in remove():
```c
static int kotesh_oom_probe(struct platform_device *pdev)
{
    /* use devm_ — automatically freed on device remove */
    data = devm_kmalloc(&pdev->dev, size, GFP_KERNEL);
    if (!data)
        return -ENOMEM;   /* clean failure — no leak */
    return 0;
}
/* no remove() needed — devm_ handles cleanup */
```

### For large allocations — check available memory first:
```c
/* Check if enough memory before large alloc */
if (si_mem_available() < (size >> PAGE_SHIFT)) {
    pr_err("not enough memory\n");
    return -ENOMEM;
}
```

---

## 🧠 Interview Explanation

> Out of Memory occurs when the kernel exhausts all available RAM and swap and
> cannot reclaim enough through page cache eviction. There are two OOM
> scenarios: a page allocation failure where a large contiguous allocation fails
> but the system continues (kmalloc returns NULL), and a full OOM where the OOM
> killer fires, selects the highest-scoring process by RSS size, kills it, and
> reclaims its memory. In our lab we exhausted 945 MB of 985 MB total RAM
> through unreclaimable slab allocations, triggering a page allocation failure
> for order:8 (1MB contiguous) but not a full OOM kill because the probe()
> function returned after kmalloc failed, releasing pressure. The key diagnostic
> is `Slab: ~987MB` and `SUnreclaim: ~978MB` in /proc/meminfo — almost all RAM
> consumed by unreclaimable kernel slab. In BSP driver development, always use
> `devm_kmalloc()` for allocations so they are automatically freed on device
> removal, always handle NULL returns from kmalloc, and for production embedded
> systems set `panic_on_oom=2` with a watchdog timeout for automatic recovery.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_oom.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/kotesh-panic-driver.bb` |

---

## ✅ Key Diagnostic Commands

```bash
# Full memory overview
cat /proc/meminfo

# Quick memory summary
free -m

# Watch memory in real time
watch -n1 free -m

# Check OOM score of processes
for p in /proc/[0-9]*/oom_score; do
    echo "$p: $(cat $p)"
done | sort -t: -k2 -rn | head -10

# Check current OOM policy
cat /proc/sys/vm/panic_on_oom

# Check slab usage
cat /proc/slabinfo | sort -k3 -rn | head -20

# dmesg OOM events
dmesg | grep -i "out of memory\|oom\|page allocation failure\|killed process"
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
| 08 | Double Free | `dead000000000100` in registers + Oops cascade | ✅ Cascade |
| 09 | OOM | `page allocation failure: order:N` or `Killed process` | ❌ Soft / ✅ Hard |

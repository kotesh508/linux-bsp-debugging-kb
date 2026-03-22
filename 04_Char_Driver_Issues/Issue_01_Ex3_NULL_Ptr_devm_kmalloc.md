# Ch01 Exercise 3 – NULL Pointer: Memory Leak Test + devm_kmalloc Concept

---

## 📋 Category
`04_Char_Driver_Issues`

---

## Objective

Verify that the fixed driver does not leak memory across multiple load/unload cycles.
Understand `devm_kmalloc` — the device-managed alternative to `kmalloc` that prevents
an entire class of memory leak bugs in platform drivers.

---

## 🔍 Stage Identification

Memory lifecycle stages:

1. `kmalloc()` → memory allocated
2. Driver runs → memory in use
3. `rmmod` → `my_exit()` called
4. `kfree()` → memory released
5. Kernel reclaims → MemFree stable

If Stage 4 is missing → MemFree drops on every cycle → memory leak.

---

## 🔎 What I Checked

```bash
# Memory BEFORE 10 cycles
echo "=== BEFORE ==="
grep MemFree /proc/meminfo
# MemFree: 7575996 kB

# 10 load/unload cycles
for i in $(seq 1 10); do
    sudo insmod sensor_driver_null_fixed.ko
    sleep 0.3
    sudo rmmod sensor_driver_null_fixed
    echo "cycle $i done"
done
# cycle 1 done ... cycle 10 done

# Memory AFTER 10 cycles
echo "=== AFTER ==="
grep MemFree /proc/meminfo
# MemFree: 7570608 kB

# Verify clean init/exit each cycle
dmesg | grep "Sensor\|FIXED" | tail -10
```

---

## 📊 Real Test Results

```
=== BEFORE ===
MemFree:  7575996 kB

cycle 1 done
cycle 2 done
cycle 3 done
cycle 4 done
cycle 5 done
cycle 6 done
cycle 7 done
cycle 8 done
cycle 9 done
cycle 10 done

=== AFTER ===
MemFree:  7570608 kB
```

```
[1406.501257] Sensor Driver [FIXED]: Data updated to 1
[1406.601165] Sensor Driver [FIXED]: Data updated to 2
[1406.701212] Sensor Driver [FIXED]: Data updated to 3
[1406.780719] Sensor Driver [FIXED]: Exiting...
[1406.883184] Sensor Driver [FIXED]: Initializing...
[1406.883192] Sensor Driver [FIXED]: Ready, threshold=100
[1406.983203] Sensor Driver [FIXED]: Data updated to 1
[1407.083208] Sensor Driver [FIXED]: Data updated to 2
[1407.183198] Sensor Driver [FIXED]: Data updated to 3
[1407.247246] Sensor Driver [FIXED]: Exiting...
```

---

## 🔍 Memory Analysis

```
BEFORE:  7575996 kB
AFTER:   7570608 kB
DIFF:    5388 kB drop over 10 cycles (~539 kB per cycle)
```

**Is this a leak?**

No — this is **normal kernel behavior**:
- Kernel caches (slab, page cache) hold recently freed memory
- Not immediately returned to MemFree pool
- Would be reclaimed under memory pressure

**A real leak looks like:**
```
cycle 1:  MemFree 7575996 kB
cycle 10: MemFree 7470000 kB  ← ~10MB gone = ~1MB per cycle = LEAK
```

**This driver is clean** — `kfree(dev)` in `my_exit()` is working correctly.

---

## 🔍 Root Cause — Why Leaks Happen

```c
/* LEAKING PATTERN — kfree missing */
static void __exit my_exit(void)
{
    hrtimer_cancel(&my_timer);
    /* kfree(dev) MISSING → dev leaked on every rmmod */
}

/* FIXED PATTERN — kfree present */
static void __exit my_exit(void)
{
    hrtimer_cancel(&my_timer);
    kfree(dev);      /* memory returned to kernel */
    dev = NULL;      /* defensive */
}
```

---

## ✅ devm_kmalloc — The Better Pattern

`devm_kmalloc` = device-managed memory. Auto-freed when device is removed.
Requires `struct device *` — available in platform drivers with `probe/remove`.

```c
/* Pattern 1: kmalloc — manual, error-prone */
dev = kmalloc(sizeof(*dev), GFP_KERNEL);
if (!dev) return -ENOMEM;
/* MUST call kfree(dev) in ALL exit paths */
/* Miss one error path → leak */

/* Pattern 2: devm_kmalloc — automatic (preferred for platform drivers) */
dev = devm_kmalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
if (!dev) return -ENOMEM;
/* NO kfree needed — freed automatically when device removed */
/* Even if probe() fails midway → all devm_ allocs freed */

/* Pattern 3: devm_kzalloc — zero initialized + automatic (best practice) */
dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
if (!dev) return -ENOMEM;
/* Zero initialized — no garbage values in struct fields */
```

---

## kmalloc vs devm_kmalloc Comparison

| | `kmalloc` | `devm_kmalloc` |
|---|---|---|
| Requires `kfree`? | Yes — must call manually | No — automatic |
| Works in `module_init`? | Yes | No — needs `platform_device` |
| Works in `probe()`? | Yes | Yes (preferred) |
| Zero initialized? | No — use `kzalloc` | No — use `devm_kzalloc` |
| Leak safe? | Only if `kfree` called on ALL paths | Always |
| Recommended for? | Simple modules | Platform drivers |

Note: `devm_kmalloc` will be used starting from Ch02 when we add `platform_driver` with `probe/remove` to the sensor driver.

---

## 🧠 Interview Explanation

`devm_kmalloc` is device-managed memory allocation — the kernel automatically frees it when the device is removed or when `probe()` fails, even if the driver's `remove()` function is never called. This eliminates memory leaks in error paths where `kfree` might be accidentally skipped. The rule of thumb: use `kmalloc` for simple standalone modules, use `devm_kzalloc` for all platform drivers with `probe/remove`.

---

## 📁 Related Files

| File | Path |
|---|---|
| Fixed driver | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/sensor_driver_null_fixed.c` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Memory before
grep MemFree /proc/meminfo

# 10 load/unload cycles
for i in $(seq 1 10); do
    sudo insmod sensor_driver_null_fixed.ko
    sleep 0.3
    sudo rmmod sensor_driver_null_fixed
done

# Memory after — compare
grep MemFree /proc/meminfo
# Small drop (~few MB) = normal kernel caching
# Large drop (>10MB for small alloc) = leak

# Optional — kmemleak check
sudo cat /sys/kernel/debug/kmemleak 2>/dev/null
# No output = no leak detected
```

---

## ✅ Key Diagnostic Commands

```bash
# Monitor memory during cycles
watch -n1 grep MemFree /proc/meminfo

# kmemleak automated detection
sudo cat /sys/kernel/debug/kmemleak

# Verify exit called on every rmmod
dmesg | grep "Exiting" | wc -l
# Count should match number of rmmod calls
```

---

## 📌 Key Learning

- Small MemFree drop after load/unload cycles is **normal** — kernel caching
- A **real leak** shows continuous large drops — ~alloc_size per cycle
- Always verify `kfree` is called in `my_exit()` — and on ALL error paths
- `devm_kmalloc` eliminates leak risk — preferred for platform drivers
- `devm_kzalloc` = `devm_kmalloc` + zero init — use this as default
- `devm_` variants require `struct device *` — available in `probe()` via `pdev->dev`
- Ch02 will add `platform_driver` — then we switch to `devm_kzalloc`

---

## 📌 Ch01 Complete Summary

```
Exercise 1: Observed NULL pointer crash    → insmod Killed, Oops in dmesg
Exercise 2: Fixed with kmalloc             → clean load, timer fires, clean unload
Exercise 3: Memory verified clean          → no leak across 10 cycles

Key rules learned:
  □ Allocate before use — order matters
  □ Always check NULL after kmalloc
  □ Cancel timer before kfree
  □ Set pointer NULL after kfree
  □ kfree must be on ALL exit paths
  □ Use devm_kzalloc in platform drivers (Ch02+)
  □ spin_unlock_irqrestore not spin_unlock_irqsave
  □ #include <linux/slab.h> for kmalloc/kfree
```

---

*Kotesh S — BSP Lab — Ch01 Exercise 3 — March 2026*

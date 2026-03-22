# Ch01 Exercise 2 – NULL Pointer: Fix with kmalloc + NULL Check + kfree

---

## 📋 Category
`04_Char_Driver_Issues`

---

## 🔴 Symptom (Before Fix — from Exercise 1)

```
BUG: kernel NULL pointer dereference, address: 0000000000000000
#PF: supervisor write access in kernel mode
Oops: 0002 [#1] SMP PTI
RIP: 0010:my_init+0x16/0x1000 [sensor_driver_null_buggy]
insmod: Killed
```

---

## ✅ Expected After Fix

```
[  195.449769] Sensor Driver [FIXED]: Initializing...
[  195.449773] Sensor Driver [FIXED]: Ready, threshold=100
[  214.350115] Sensor Driver [FIXED]: Data updated to 189
[  214.450116] Sensor Driver [FIXED]: Data updated to 190
[  214.550118] Sensor Driver [FIXED]: Data updated to 191
...
[  261.410645] Sensor Driver [FIXED]: Exiting...
```

Clean load → timer fires every 100ms → clean unload. No Oops. No panic.

---

## 🔍 Stage Identification

Driver lifecycle stages:

1. `module_init()` called
2. Memory allocated (`kmalloc`) ← **fixed here**
3. NULL check after allocation ← **fixed here**
4. Pointer used safely (`dev->value`)
5. Hardware initialized (hrtimer)
6. Driver ready

Fix restored correct order — **allocate before use**.

---

## 🔎 What I Checked

```bash
# 1. Build fixed module
cd ~/30days_workWith_BSP/my_projects/ch01_null_pointer
make clean && make
# Clean build — no errors

# 2. Load fixed module
sudo insmod sensor_driver_null_fixed.ko
echo "exit code: $?"
# exit code: 0  ← success

# 3. Verify init messages
dmesg | grep "Initializ\|Ready" | tail -3
# [  195.449769] Sensor Driver [FIXED]: Initializing...
# [  195.449773] Sensor Driver [FIXED]: Ready, threshold=100

# 4. Verify timer firing every 100ms
dmesg | grep "FIXED" | tail -10
# Data updated to 189, 190, 191... every 100ms

# 5. Clean unload
sudo rmmod sensor_driver_null_fixed
echo "rmmod exit: $?"
# rmmod exit: 0

# 6. Verify exit message
dmesg | grep "Exiting" | tail -2
# [  261.410645] Sensor Driver [FIXED]: Exiting...
```

✔ `exit code: 0` → module loaded successfully

✔ `Initializing...` → `my_init()` executed fully

✔ `Ready, threshold=100` → `dev->threshold` accessible — memory valid

✔ Timer firing every 100ms → `dev` pointer valid in callback context

✔ `rmmod exit: 0` → clean unload

✔ `Exiting...` → `hrtimer_cancel` + `kfree` executed

---

## 🔍 Root Cause (From Exercise 1)

```c
/* BUGGY — wrong order */
static int __init my_init(void)
{
    dev->value = 0;               /* CRASH: use before allocate */
    dev = kmalloc(...);           /* too late — already crashed */
}
```

---

## ✅ Fix

```c
/* FIXED — correct order */
static int __init my_init(void)
{
    pr_info("Sensor Driver [FIXED]: Initializing...\n");

    dev = kmalloc(sizeof(*dev), GFP_KERNEL);  /* 1. allocate FIRST */
    if (!dev)                                  /* 2. check NULL */
        return -ENOMEM;

    dev->value = 0;                            /* 3. use AFTER */
    dev->threshold = 100;

    spin_lock_init(&my_lock);
    hrtimer_init(&my_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
    my_timer.function = timer_callback;
    hrtimer_start(&my_timer, ms_to_ktime(100), HRTIMER_MODE_REL);

    pr_info("Sensor Driver [FIXED]: Ready, threshold=%d\n", dev->threshold);
    return 0;
}

static void __exit my_exit(void)
{
    pr_info("Sensor Driver [FIXED]: Exiting...\n");
    hrtimer_cancel(&my_timer);    /* cancel timer BEFORE freeing memory */
    kfree(dev);                   /* free allocated memory */
    dev = NULL;                   /* defensive NULL after free */
}
```

---

## ⚠️ Mistakes Made During This Exercise

```
1. Wrong order — used dev before kmalloc:
   dev->value = 0;        ← crash
   dev = kmalloc(...);    ← too late

2. Missing header — forgot #include <linux/slab.h> for kmalloc/kfree

3. Name conflict — struct named sensor_data AND global int sensor_data
   → renamed int to sensor_count

4. Wrong function name — spin_unlock_irqsave() does not exist
   → correct is spin_unlock_irqrestore()

5. Missing my_timer.function = timer_callback — timer never fired

6. return -ENOMEM without if(!dev) check — always returned error
```

These are real mistakes — documenting them helps remember the patterns.

---

## 🧠 Interview Explanation

The fix allocates memory with `kmalloc` before the pointer is used, checks the return value for NULL, and frees the memory in the exit function with `kfree`. The critical rule is order — allocate first, check NULL, then use. Setting the pointer to NULL after `kfree` prevents use-after-free. The timer must be cancelled before `kfree` to prevent the callback from accessing freed memory after it is freed.

---

## 📁 Related Files

| File | Path |
|---|---|
| Fixed driver | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/sensor_driver_null_fixed.c` |
| Makefile | `~/30days_workWith_BSP/my_projects/ch01_null_pointer/Makefile` |

---

## 🧪 How to Reproduce

```bash
# Build
cd ~/30days_workWith_BSP/my_projects/ch01_null_pointer
make clean && make

# Load
sudo insmod sensor_driver_null_fixed.ko

# Verify timer firing
dmesg | grep "FIXED" | tail -10

# Unload
sudo rmmod sensor_driver_null_fixed

# Verify clean exit
dmesg | grep "Exiting" | tail -2
```

---

## ✅ Key Diagnostic Commands

```bash
# Verify successful load
echo "exit code: $?"

# Verify init ran
dmesg | grep "Initializing"

# Verify memory valid
dmesg | grep "Ready, threshold"

# Verify timer firing
dmesg | grep "Data updated" | tail -5

# Verify clean unload
dmesg | grep "Exiting"
```

---

## 📌 Key Learning

- **Order matters** — always allocate before use, free before exit
- `kmalloc` + `if (!ptr) return -ENOMEM` is the standard safe pattern
- Cancel timers **before** `kfree` — prevents callback accessing freed memory
- Set pointer to `NULL` after `kfree` — prevents use-after-free
- `spin_unlock_irqrestore` not `spin_unlock_irqsave` — they are a pair
- Name conflicts between struct and variable cause silent bugs
- `#include <linux/slab.h>` required for `kmalloc`/`kfree`

---

*Kotesh S — BSP Lab — Ch01 Exercise 2 — March 2026*

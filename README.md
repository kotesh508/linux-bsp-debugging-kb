# Linux BSP & Kernel Debugging Knowledge Base

> **Hands-on kernel debugging lab — real issues, real crashes, real fixes.**
> Every issue reproduced on actual hardware (ThinkPad T460s) and QEMU ARM64.

---

## 👤 About

**Kotesh S** — Embedded Systems & Linux Engineer  
Transitioning from bare-metal embedded to Linux BSP/kernel driver development.  
Author: *Embedded Linux / Kernel Debugging — Real Problems from BSP to Kernel* (Part 1 & 2)

📧 Connect: [github.com/kotesh408](https://github.com/kotesh408)

---

## 🎯 What This Repo Is

A **practical debugging knowledge base** built by reproducing and documenting real Linux kernel issues — not from tutorials, but from actual crashes observed on hardware and QEMU.

Each issue follows the same structure:
```
Symptom (real log output) → Stage Identification → What I Checked → Root Cause → Fix → Interview Explanation
```

**Target roles:** BSP Engineer · Linux Kernel Developer · Embedded Linux Engineer · Device Driver Engineer

---

## 🛠️ Lab Environment

| Component | Details |
|---|---|
| Host Machine | ThinkPad T460s — Ubuntu 22.04 |
| Kernel | linux-6.6 (cross-compiled) + 5.15.0 (host) |
| Architecture | ARM64 (QEMU) + x86_64 (host) |
| Emulator | QEMU ARM64 — `qemu-system-aarch64` |
| Rootfs | Yocto Project — `core-image-minimal` |
| Toolchain | Arm GNU Toolchain 14.3 |
| Bootloader | U-Boot |

---

## 📂 Repository Structure

```
linux-bsp-debugging-kb/
│
├── 01_Boot_Issues/              # Kernel boot failures — console, rootfs, init
│   ├── Issue_01_No_Console.md
│   ├── Issue_02_Wrong_Root_Device.md
│   ├── Issue_03_Ext4_As_Module.md
│   ├── Issue_04_Missing_Block_Driver.md
│   ├── Issue_05_No_Init_Found.md
│   └── REPRODUCE_01_Boot_Issues.sh
│
├── 02_DTS_Driver_Issues/        # Device Tree + platform driver probe failures
│   ├── Issue_01_Compatible_Mismatch.md
│   ├── Issue_02_Disabled_Node.md
│   ├── Issue_03_Missing_Reg_Property.md
│   ├── Issue_04_Wrong_Interrupt_Number.md
│   ├── Issue_05_Probe_Deferral.md
│   ├── Issue_06_Missing_Clock.md
│   ├── Issue_07_Missing_Regulator.md
│   ├── Issue_08_Missing_CONFIG_OF.md
│   ├── Issue_09_Driver_Not_In_Image.md
│   ├── Issue_10_Compatible_String_Mismatch.md
│   ├── Issue_11_Interrupt_Cell_Format.md
│   ├── Issue_12_Platform_Driver_Probe_Cycle.md
│   └── REPRODUCE_02_DTS_Issues.sh
│
├── 03_Panic_Analysis/           # Kernel panics, Oops, memory corruption
│   ├── Panic_Issue_01_NULL_Pointer_Dereference.md
│   ├── Panic_Issue_02_Stack_Overflow.md
│   ├── Panic_Issue_03_BUG_ON_WARN_ON.md
│   ├── Panic_Issue_04_Divide_by_Zero.md
│   ├── Panic_Issue_05_Hung_Task.md
│   ├── Panic_Issue_06_Oops_vs_Panic.md
│   ├── Panic_Issue_07_Use_After_Free.md
│   ├── Panic_Issue_08_Double_Free.md
│   ├── Panic_Issue_09_OOM.md
│   ├── Panic_Issue_10_Unaligned_Access.md
│   └── REPRODUCE_03_Panic_Issues.sh
│
├── 04_Char_Driver_Issues/       # Character driver debugging — from book exercises
│   ├── Issue_01_Ex1_NULL_Ptr_Uninitialized.md   # real crash on ThinkPad
│   ├── Issue_01_Ex2_NULL_Ptr_kmalloc_Fix.md     # real fix verified
│   ├── Issue_01_Ex3_NULL_Ptr_devm_kmalloc.md    # memory leak test
│   └── (Ch02–Ch10 in progress)
│
├── BSP_Diagnostic_Reference.md  # Master cheat sheet — all 30 issues
├── DEBUG_COMMANDS_REFERENCE.md  # Debug commands by issue type
├── boot_qemu.sh                 # QEMU boot script
├── bsp-session.sh               # Session setup script
└── README_QEMU_Workflow.md      # QEMU workflow guide
```

---

## 📊 Issues Documented

| Category | Issues | Reproduced | Status |
|---|---|---|---|
| Boot Issues | 5 | ✅ QEMU | ✅ Complete |
| DTS / Driver Issues | 12 | ✅ QEMU | ✅ Complete |
| Panic Analysis | 10 | ✅ QEMU | ✅ Complete |
| Char Driver Issues | 36 (book exercises) | ✅ ThinkPad | 🔄 In Progress |
| **Total** | **63** | | |

---

## 🔥 Highlights

### Real Kernel Crashes — Not Simulated
Every issue was actually reproduced. Example from Ch01:
```
[58449.720223] BUG: kernel NULL pointer dereference, address: 0000000000000000
[58449.720231] #PF: supervisor write access in kernel mode
[58449.720243] Oops: 0002 [#1] SMP PTI
[58449.720255] RIP: 0010:my_init+0x16/0x1000 [sensor_driver_null_buggy]
```

### Sensor Driver — Evolved Chapter by Chapter
Starting from a basic hrtimer + spinlock sensor driver, each chapter adds one new feature:
```
Ch01 → kmalloc/kfree (NULL pointer)
Ch02 → platform_driver + DTS (driver probe)
Ch03 → GPIO control
Ch04 → IRQ handler
Ch05 → /dev character device
Ch06 → memory leak detection
Ch07 → stack overflow prevention
Ch08 → copy_to/from_user
Ch09 → kernel config dependencies
Ch10 → boot delay optimization
```

### Interview-Ready Documentation
Every issue includes a 2-3 line **Interview Explanation** — written to answer real BSP engineer interview questions.

---

## 🚀 How to Use This Repo

### Quick Reference
```bash
# Find your error in the master cheat sheet
cat BSP_Diagnostic_Reference.md

# Find the right debug command
cat DEBUG_COMMANDS_REFERENCE.md
```

### Reproduce an Issue
```bash
# Set up session
source ~/BSP-Lab/bsp-session.sh

# Boot QEMU
./boot_qemu.sh

# Run reproduce script for a category
bash 01_Boot_Issues/REPRODUCE_01_Boot_Issues.sh
```

### Read an Issue
Each `.md` file is self-contained:
1. **Symptom** — exact log output
2. **Stage Identification** — where in boot/probe/runtime it failed
3. **What I Checked** — diagnostic commands with real output
4. **Root Cause** — explanation with code
5. **Fix** — exact change made
6. **Interview Explanation** — 2-3 lines for interviews

---

## 📚 Related Work

| Project | Description |
|---|---|
| [embedded-linux-bsp-30days](https://github.com/kotesh408/embedded-linux-bsp-30days) | 30-day BSP learning journey |
| *Embedded Linux / Kernel Debugging* (Book) | Practical field guide — Part 1 & Part 2 |

---

## 🛠️ Technologies

`Linux Kernel` `Device Tree (DTS/DTB)` `QEMU` `Yocto Project` `ARM64`
`U-Boot` `Platform Driver` `Character Driver` `hrtimer` `spinlock`
`kmalloc` `kfree` `IRQ` `GPIO` `GDB` `objdump` `addr2line`

---

## 📈 Progress

- [x] Boot Issues — 5 issues
- [x] DTS / Driver Issues — 12 issues  
- [x] Panic Analysis — 10 issues
- [x] BSP Diagnostic Reference — 30 issue cheat sheet
- [x] Debug Commands Reference
- [ ] Char Driver Issues — 36 exercises (in progress)
- [ ] Kernel patch upstream contribution
- [ ] Yocto Project certification

---

*Built with real crashes, real fixes, and real debugging sessions.*
*Updated continuously — March 2026*

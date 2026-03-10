# Panic Issue 10 — Bad Pointer / Unaligned Access

---

## 📋 Category
`03_Panic_Analysis`

---

## 🔴 Symptom Output

```
[    8.453489] KOTESH_UNALIGNED: probe called
[    8.454189] KOTESH_UNALIGNED: forcing unaligned memory access
[    8.479630] KOTESH_UNALIGNED: address = (____ptrval____)
[    8.480199] KOTESH_UNALIGNED: read value 16777216

qemuarm64 login: root   ← SYSTEM SURVIVED!
```

**Key observation:** ARM64 handled the unaligned access in hardware — no fault,
no Oops, no panic. The read succeeded but returned `16777216` (0x01000000)
instead of the expected value — this is a **byte-swapped/misread result** due
to the unaligned address crossing a cache line boundary.

---

## 🔎 Panic Type
**Unaligned Memory Access** — accessing a multi-byte value at an address not
aligned to its natural size. Behavior is architecture-dependent:

| Architecture | Unaligned behavior |
|---|---|
| ARM64 (our case) | Hardware fixup — transparent, no fault |
| ARM32 | SIGBUS or hardware fixup (config dependent) |
| x86/x86_64 | Always transparent — hardware handles it |
| MIPS | Bus error (SIGBUS) — always fatal |
| RISC-V | Trap to kernel — software fixup or fault |

---

## 🔎 Driver Source — What We Did

```c
static int kotesh_unaligned_probe(struct platform_device *pdev)
{
    u8 buf[8] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07};
    u32 *ptr;
    u32 val;

    pr_info("KOTESH_UNALIGNED: probe called\n");
    pr_info("KOTESH_UNALIGNED: forcing unaligned memory access\n");

    /* Force unaligned: point u32 ptr at offset +1 (not 4-byte aligned) */
    ptr = (u32 *)(buf + 1);

    pr_info("KOTESH_UNALIGNED: address = %px\n", ptr);

    /* Read 4 bytes from unaligned address */
    val = *ptr;   /* reads bytes [1,2,3,4] = 0x01020304 */

    pr_info("KOTESH_UNALIGNED: read value %u\n", val);
    /* Expected: 0x01020304 = 16909060 */
    /* Got:      0x01000000 = 16777216 — byte order/alignment issue! */

    return 0;
}
```

### Why the value was 16777216 (0x01000000) instead of 16909060 (0x01020304)?

ARM64 transparently fixed up the unaligned access but the result reflects
how the hardware fetches the data across the alignment boundary. The exact
value depends on cache line alignment, endianness, and how the fixup works.
The point is: **the data is wrong** — silent data corruption, no crash.

---

## 🔎 ARM64 Unaligned Access — Deep Dive

### ARM64 SCTLR_EL1.A bit (Alignment check):
```
SCTLR_EL1.A = 0  → Unaligned access allowed (hardware fixup)  ← Linux default
SCTLR_EL1.A = 1  → Unaligned access causes SIGBUS fault
```

Linux ARM64 boots with `A=0` — unaligned accesses are **silently fixed up**
by hardware. This means:
- No crash
- No warning
- **Wrong data** silently returned
- Performance penalty (multiple bus transactions)

### Enable strict alignment checking at boot:
```bash
# Add to kernel cmdline to enable alignment faults:
-append "console=ttyAMA0 root=/dev/vda rw alignment=2"
```

With `alignment=2` the kernel enables SIGBUS on unaligned access:
```
Alignment trap: kotesh_unaligned (probe) PC=0x... Instr=0xe5912000
  Address=0x... FSR 0x001
Bus error
```

---

## 🔎 Bad Pointer Scenarios — Actual Crashes

While unaligned access survived, **bad pointers** do cause panics:

### 1. Kernel address in userspace range:
```c
/* Pointer with value in userspace range (< 0xffff000000000000 on ARM64) */
u32 *bad = (u32 *)0x12345678;
*bad = 42;
/* → Unable to handle kernel paging request at virtual address 0x12345678 */
/* → EC = 0x25: DABT */
```

### 2. Completely invalid kernel address:
```c
/* Non-canonical address */
u32 *bad = (u32 *)0xdeadbeefdeadbeef;
*bad = 42;
/* → Unable to handle kernel paging request */
/* → pgd=0000000000000000 — no page table entry */
```

### 3. ERR_PTR — error-encoded pointer:
```c
struct clk *clk = clk_get(dev, "apb");
/* If clk_get fails, returns ERR_PTR(-ENOENT) = 0xfffffffffffffffе */
clk->rate = 1000;   /* BUG: should check IS_ERR(clk) first! */
/* → NULL pointer dereference at 0xfffffffffffffffe + offset */
```

### 4. Hardware register address without ioremap:
```c
/* Direct physical address access — ALWAYS wrong in kernel */
u32 *reg = (u32 *)0x20000000;  /* physical address */
*reg = 1;
/* → Unable to handle kernel paging request */
/* Physical addresses not mapped in kernel virtual address space */
/* Must use ioremap() first! */
```

---

## 🔎 Correct Hardware Register Access in BSP Drivers

### Wrong — direct physical address:
```c
/* NEVER do this */
u32 *reg = (u32 *)0x20000000;
writel(1, reg);   /* crash! */
```

### Correct — use ioremap via devm_ioremap_resource:
```c
static int probe(struct platform_device *pdev)
{
    struct resource *res;
    void __iomem *base;

    /* Get resource from DTS reg property */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!res)
        return -ENODEV;

    /* Map physical address to kernel virtual address */
    base = devm_ioremap_resource(&pdev->dev, res);
    if (IS_ERR(base))
        return PTR_ERR(base);

    /* Now safe to access */
    writel(1, base + REG_CTRL);
    val = readl(base + REG_STATUS);
}
```

---

## 🔎 Alignment Issues in Real BSP Work

### DMA buffer alignment:
```c
/* Wrong — kmalloc may not give cache-aligned buffer */
u8 *buf = kmalloc(size, GFP_KERNEL);
dma_map_single(dev, buf, size, DMA_TO_DEVICE);  /* may fail or corrupt */

/* Correct — use dma_alloc_coherent for DMA buffers */
buf = dma_alloc_coherent(dev, size, &dma_addr, GFP_KERNEL);
```

### Structure packing alignment:
```c
/* Wrong — packed struct loses alignment */
struct __packed bad_struct {
    u8  flag;
    u32 value;   /* now at offset 1 — unaligned! */
};

/* Correct — let compiler insert padding */
struct good_struct {
    u8  flag;
    u8  _pad[3];  /* explicit padding */
    u32 value;    /* now at offset 4 — aligned! */
};
```

### MMIO register access — always use readl/writel:
```c
/* Wrong — may generate unaligned access on some architectures */
u32 val = *(volatile u32 *)reg_addr;

/* Correct — guaranteed aligned, ordered, and portable */
u32 val = readl(reg_addr);
writel(val, reg_addr);
```

---

## 🔎 ARM64 vs ARM32 Alignment Behavior

| Scenario | ARM64 | ARM32 |
|---|---|---|
| Unaligned u16/u32/u64 | HW fixup, no fault | HW fixup (modern) or SIGBUS |
| Packed struct field | HW fixup | May SIGBUS |
| MMIO unaligned | Fault — MMIO must be aligned | Fault |
| DMA buffer unaligned | Silent corruption | Silent corruption or DMA abort |
| `__packed` struct | Works, slower | May SIGBUS on old ARM |

**Key rule:** Never rely on hardware fixup. Use proper alignment for:
1. Performance (unaligned = multiple bus transactions)
2. Portability (works on ARM64, may crash on MIPS/RISC-V)
3. MMIO (always strictly aligned — no fixup possible)

---

## 🔎 How to Detect Alignment Issues

```bash
# Enable alignment fault reporting at runtime
echo 2 > /proc/cpu/alignment    # Report + fixup
echo 3 > /proc/cpu/alignment    # Report + SIGBUS (strict)

# Check alignment fault statistics
cat /proc/cpu/alignment

# Boot with strict alignment:
# kernel cmdline: alignment=2

# Find unaligned MMIO access (perf):
perf stat -e alignment-faults ./your_driver_test
```

---

## 🧠 Interview Explanation

> Unaligned memory access occurs when a multi-byte value is read from or
> written to an address not aligned to its natural size — for example reading
> a 4-byte u32 from an odd address. On ARM64, Linux boots with hardware
> alignment fixup enabled (SCTLR_EL1.A=0), so unaligned accesses are
> transparently handled by the CPU without faulting, but at a performance cost
> and with potential for subtle data corruption as we saw — the read value
> was wrong. On architectures like MIPS or strict ARM32 configurations, the
> same access would cause a SIGBUS. In BSP driver development the most
> common bad pointer scenarios are: accessing physical MMIO addresses directly
> without ioremap (must always use devm_ioremap_resource), using ERR_PTR
> values without checking IS_ERR first, and DMA buffers that are not
> cache-line aligned causing data corruption. The correct pattern for MMIO
> is always readl/writel which guarantee alignment, ordering, and portability
> across all architectures.

---

## 📁 Related Files

| File | Path |
|------|------|
| Driver source | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/files/kotesh_unaligned.c` |
| DTS source | `~/dtstest/qemu-virt.dts` |
| Recipe | `~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver/kotesh-panic-driver.bb` |

---

## ✅ Key Diagnostic Commands

```bash
# Check alignment fault count
cat /proc/cpu/alignment

# Enable alignment fault reporting
echo 2 > /proc/cpu/alignment

# Check if kernel was built with strict alignment
zcat /proc/config.gz | grep CONFIG_ARM64_SW_TTBR0_PAN

# Find misaligned accesses with perf
perf stat -e alignment-faults -a sleep 5

# Check ioremap usage in driver
cat /proc/iomem
```

---

## 📌 Complete Panic Issue Summary — ALL 10 DONE ✅

| # | Panic Type | Key Signature | Fatal? | Detection Tool |
|---|---|---|---|---|
| 01 | NULL Pointer | `Unable to handle kernel NULL pointer dereference` | Oops | dmesg |
| 02 | Stack Overflow | `kernel stack overflow` + `Insufficient stack space` | ✅ Always | dmesg |
| 03 | WARN_ON/BUG_ON | `cut here` + `WARNING` / `kernel BUG at` | ❌/✅ | dmesg |
| 04 | Divide by Zero | `Unexpected kernel BRK exception at EL1` | ✅ Yes | dmesg |
| 05 | Hung Task | `INFO: task blocked for more than N seconds` | ❌ Warning | dmesg / ps |
| 06 | Oops → Panic | `Kernel panic - not syncing` | Depends `panic_on_oops` | dmesg |
| 07 | Use After Free | Silent — wrong data read back | ❌ Silent | KASAN |
| 08 | Double Free | `dead000000000100` in regs + Oops cascade `[#N]` | ✅ Cascade | dmesg / KASAN |
| 09 | OOM | `page allocation failure: order:N` / `Killed process` | ❌/✅ | dmesg / /proc/meminfo |
| 10 | Unaligned Access | Silent on ARM64 — wrong data / SIGBUS on MIPS | ❌ ARM64 / ✅ MIPS | /proc/cpu/alignment |

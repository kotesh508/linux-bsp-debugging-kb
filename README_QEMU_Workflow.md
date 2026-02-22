# QEMU Workflow – Boot Issue Practice Guide

---

# 1️⃣ Enter Yocto Build Environment

Every new terminal session:

```bash
cd ~/poky
source oe-init-build-env
```

---

# 2️⃣ Build Image (If Needed)

```bash
bitbake core-image-minimal
```

---

# 3️⃣ Navigate to Image Directory

```bash
cd ~/poky/build/tmp/deploy/images/qemuarm64
```

Check files:

```bash
ls
```

You should see:
- Image
- core-image-minimal-qemuarm64.ext4

---

# 4️⃣ Normal Working QEMU Boot Command

```bash
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a53 \
  -smp 2 \
  -m 1024 \
  -kernel Image \
  -drive if=none,file=core-image-minimal-qemuarm64.ext4,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -append "console=ttyAMA0 root=/dev/vda rw loglevel=8 panic=-1" \
  -nographic
```

This is your baseline working boot command.

---

# 5️⃣ How to Intentionally Break System

## A. Wrong root device

Change:

```
root=/dev/vda
```

To:

```
root=/dev/vdb
```

Expected result:
- VFS panic
- Unable to mount root fs

---

## B. Remove console

Remove:

```
console=ttyAMA0
```

Expected result:
- No logs visible
- Kernel still running

---

## C. Wrong init

Add:

```
init=/wrong
```

Expected result:
- Kernel panic
- No init found

---

# 6️⃣ Capture Logs After Panic

After panic appears:

Manually copy last 20–30 lines.

Save into:

```
~/BSP-Lab/04_Logs/Issue_xxx.log
```

---

# 7️⃣ Documentation Flow for Each Issue

For every issue:

1. Break system intentionally
2. Observe error
3. Identify boot stage
4. Debug logically
5. Fix issue
6. Verify system boots
7. Write .md documentation
8. Commit using Git

---

# 8️⃣ Git Commit Procedure

```bash
cd ~/BSP-Lab
git add .
git commit -m "Boot Issue XX: Description"
```

---

# 9️⃣ Boot Stage Identification Reference

| Symptom | Stage |
|----------|--------|
| No logs | Console stage |
| VFS panic | Root filesystem |
| unknown-block | Block driver |
| No init | Userspace init |
| Reboot loop | Panic / Watchdog |
| NULL pointer | Driver crash |

---

# 🔟 Golden Rule

Never fix immediately.

Always:
- Observe
- Think
- Identify stage
- Then fix

This builds debugging confidence.

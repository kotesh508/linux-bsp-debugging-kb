# Boot Issue 02 – Wrong root= Parameter (unknown-block(0,0))

## Objective
Reproduce kernel panic caused by incorrect root device parameter.

---

## Environment
- MACHINE: qemuarm64
- Kernel: linux-yocto 5.15
- Boot method: Direct QEMU boot
- Filesystem: ext4

---

## Working Boot Command

```bash
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a53 \
  -smp 2 \
  -m 1024 \
  -kernel Image \
  -drive if=none,file=core-image-minimal-qemuarm64.ext4,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -append "console=ttyAMA0 root=/dev/vda rw loglevel=8" \
  -nographic
How I Broke It

Changed:

root=/dev/vda

To:

root=/dev/vdb

Observed Logs

VFS: Unable to mount root fs on unknown-block(0,0)
Kernel panic - not syncing


What Happened Internally

Kernel parsed root=/dev/vdb

No such block device exists

Kernel could not resolve device

Major/Minor defaulted to (0,0)

VFS mount failed

Kernel panic triggered

Why unknown-block(0,0)?

Major number = 0

Minor number = 0

Means root device not resolved at all

Fix

Restore correct root parameter:

root=/dev/vda

Reboot → System boots normally.

Interview Explanation

unknown-block(0,0) indicates that the root device specified in the root= parameter could not be resolved by the kernel. 
This usually happens due to incorrect root device configuration

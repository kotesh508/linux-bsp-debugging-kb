# Boot Issue 03 – Ext4 Compiled as Module (unknown-block(253,0))

## Objective
Reproduce kernel panic caused by compiling ext4 filesystem as module instead of built-in.

---

## Environment
- MACHINE: qemuarm64
- Kernel: linux-yocto 5.15
- Filesystem: ext4
- Block driver: virtio_blk (built-in)

---

## Step 1 – Modify Kernel Config

```bash
source oe-init-build-env
bitbake -c menuconfig virtual/kernel

Navigate to:

File Systems → The Extended 4 (ext4) filesystem

Change:

CONFIG_EXT4_FS = y

To:

CONFIG_EXT4_FS = m

Save and exit.

Step 2 – Rebuild Kernel
bitbake virtual/kernel -c compile -f
bitbake core-image-minimal
Step 3 – Boot QEMU
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
Observed Logs
fd00 11472 vda
driver: virtio_blk

VFS: Unable to mount root fs on unknown-block(253,0)
Kernel panic - not syncing
What Happened Internally

virtio_blk detected /dev/vda

Device registered with major=253 minor=0

Kernel attempted to mount ext4 rootfs

ext4 driver was a module

Modules reside inside root filesystem

Root filesystem not mounted yet

ext4 could not be loaded

Deadlock → Kernel panic

Why unknown-block(253,0)?

253 = major number of virtio block device

0 = minor number

Device exists

Mount failed due to missing filesystem driver

Fix

Rebuild kernel with ext4 built-in:

CONFIG_EXT4_FS = y

Recompile and reboot → System boots normally.

Interview Explanation

When ext4 is compiled as a module and used as root filesystem, the kernel detects the block device but cannot mount it because modules are stored inside the root filesystem. This results in VFS panic showing unknown-block(major,minor).

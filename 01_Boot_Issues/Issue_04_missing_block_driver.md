Objective

Reproduce and analyze kernel panic caused by disabling the root block driver (virtio_blk) in a qemuarm64 Yocto environment.

This experiment demonstrates what happens when the kernel cannot detect the root block device during early boot.

Environment

MACHINE: qemuarm64

Kernel: linux-yocto 5.15

Root Filesystem: ext4

Block Device: /dev/vda

Virtual Platform: QEMU (virt machine)

Background

In qemuarm64, the root filesystem is provided through a VirtIO block device.

That means:

/dev/vda is created by virtio_blk

Root mount depends on CONFIG_VIRTIO_BLK

If this driver is disabled, the kernel cannot detect the disk.

Step 1 – Disable Virtio Block Driver
source oe-init-build-env
bitbake -c menuconfig virtual/kernel

Navigate to:

Device Drivers
  → Block devices
      → Virtio block driver

Change:

CONFIG_VIRTIO_BLK = y

To:

CONFIG_VIRTIO_BLK is not set

Save and exit.

Step 2 – Rebuild Kernel and Image

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
VFS: Cannot open root device "vda" or unknown-block(0,0)
Kernel panic - not syncing: VFS: Unable to mount root fs

What Happened Internally

Kernel started successfully

QEMU provided a VirtIO disk

virtio_blk driver was not compiled

Kernel could not detect /dev/vda

No block device was registered

Root mount failed immediately

Kernel panic triggered

Why unknown-block(0,0)?

0 → No major number assigned

0 → No minor number

Kernel does not recognize any block device

Disk driver missing completely

This means:

The block device itself was never created.

Root Cause

The root block driver (virtio_blk) was disabled.

Without the block driver:

No /dev/vda

No root device

Boot cannot proceed

Fix

Re-enable VirtIO block driver:

CONFIG_VIRTIO_BLK = y

Then rebuild:

bitbake virtual/kernel -c compile -f
bitbake core-image-minimal

System boots normally.

Key Learning

For successful root filesystem boot:

Block driver must be built-in (=y)

Filesystem driver must be built-in (=y)

Missing block driver results in unknown-block(0,0)

Comparison With Other Boot Issues
Scenario	Error
Block driver missing	unknown-block(0,0)
Filesystem driver missing	unknown-block(253,0)
Wrong root device	Cannot open root device
Engineering Insight

This experiment demonstrates:

Early boot device dependency

Block layer initialization

Root mount sequence

How to interpret major/minor numbers in panic logs

Understanding these patterns helps in real-world BSP debugging and kernel bring-up.

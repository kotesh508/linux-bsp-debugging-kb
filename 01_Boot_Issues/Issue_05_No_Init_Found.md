Boot Issue 05 – No Working init Found
Objective

Reproduce and analyze kernel panic caused by specifying an invalid init= parameter during boot.

This demonstrates failure at the userspace handoff stage.

Environment

MACHINE: qemuarm64

Kernel: linux-yocto 5.15

Root Filesystem: ext4

Block Driver: virtio_blk (built-in)

Filesystem Driver: ext4 (built-in)

Symptom (Log Snippet)
EXT4-fs (vda): mounted filesystem with ordered data mode.
VFS: Mounted root (ext4 filesystem) on device 253:0.
Run /bin/doesnotexist as init process
Kernel panic - not syncing: Requested init /bin/doesnotexist failed (error -2).
Stage Identification

Boot flow stages:

Kernel start

Block driver initialization

Root filesystem mount

Execute init process

Userspace begins

Failure occurred at:

👉 Stage 4 – init execution

Root filesystem mounted successfully.
Kernel failed while starting first userspace process.

Reproduction Steps
Modify QEMU boot parameter
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a53 \
  -smp 2 \
  -m 1024 \
  -kernel tmp/deploy/images/qemuarm64/Image \
  -drive if=none,file=tmp/deploy/images/qemuarm64/core-image-minimal-qemuarm64.ext4,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -append "console=ttyAMA0 root=/dev/vda rw init=/bin/doesnotexist" \
  -serial mon:stdio \
  -nographic
What I Checked

✔ Verified block device detected:

virtio_blk virtio0: [vda] ...

✔ Verified root filesystem mounted:

VFS: Mounted root (ext4 filesystem)

✔ Confirmed kernel attempted to execute specified init path.

Root Cause

The kernel was instructed to execute:

init=/bin/doesnotexist

That binary does not exist in the root filesystem.

Kernel fallback sequence:

/sbin/init

/etc/init

/bin/init

/bin/sh

Since explicit init= was given and failed:

Error -2 (ENOENT – No such file)

Kernel panicked to prevent running without userspace

Why Error -2?

-2 corresponds to:

ENOENT → No such file or directory

So:

Device exists ✔
Filesystem mounted ✔
Executable missing ✖

Fix

Remove invalid init= parameter:

-append "console=ttyAMA0 root=/dev/vda rw"

Or specify valid init:

-append "console=ttyAMA0 root=/dev/vda rw init=/sbin/init"

System boots successfully.

Interview Explanation (2–3 Lines)

The kernel successfully mounted the root filesystem but failed to execute the first userspace process (init). Since the specified init binary did not exist, the kernel triggered a panic to prevent running without userspace. This confirms the failure occurred after root mount but before userspace initialization.

Key Learning

Block driver must work before mount

Filesystem driver must work before mount

init is the first userspace process

Boot can fail even after successful root mount

Error code helps identify root cause

This is a strong foundation example.

You now have documented:

Filesystem as module failure

Block driver missing

Wrong init path

Very clean progression 👌

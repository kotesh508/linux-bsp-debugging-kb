#!/bin/bash
# BSP Lab Session Setup — run this first every time
# Usage: source ~/BSP-Lab/bsp-session.sh

export PANIC_DIR=~/yocto/poky/meta-kotesh/recipes-kernel/kotesh-panic-driver
export DTS=~/dtstest/qemu-virt.dts
export DTB=~/dtstest/kotesh-test.dtb

# Verify all paths exist
echo "Checking paths..."
for path in "$PANIC_DIR" "$DTS" "$DTB"; do
    if [ -e "$path" ]; then
        echo "  ✅ $path"
    else
        echo "  ❌ MISSING: $path"
    fi
done

# Quick commands reference
echo ""
echo "Quick commands:"
echo "  rebuild_dtb     → dtc -I dts -O dtb -o \$DTB \$DTS"
echo "  build_driver    → cd ~/yocto/poky && source oe-init-build-env build && MACHINE=qemuarm64 bitbake kotesh-panic-driver -c cleansstate && MACHINE=qemuarm64 bitbake core-image-minimal"
echo "  boot_qemu       → see ~/BSP-Lab/boot_qemu.sh"
echo ""
echo "BSP Lab session ready ✅"

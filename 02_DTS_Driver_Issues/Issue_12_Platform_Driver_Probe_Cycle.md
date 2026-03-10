# Issue 12 — Complete Platform Driver Probe Cycle

## What Was Built
Full BSP driver bring-up cycle on QEMU ARM virt machine.

## The Chain
1. Added DTS node to qemu-virt.dts:
   my-bsp-device {
       compatible = "my-custom,bsp-device";
       status = "okay";
   };

2. Compiled DTS to DTB:
   dtc -I dts -O dtb -o qemu-virt.dtb qemu-virt.dts

3. Booted QEMU with new DTB:
   qemu-system-arm -M virt -dtb ~/dtstest/qemu-virt.dtb ...

4. Loaded driver via 9P virtio share:
   insmod /mnt/host/my_bsp_driver.ko

## Verified Output
my_bsp_driver my-bsp-device: Real Hardware Probe Successful!

## Key Learnings
- compatible string in DTS must exactly match of_match_table in driver
- QEMU does not expand ~ in paths — must use full /home/kotesh/...
- dtc warning about missing interrupt-controller is non-fatal
- 9P virtio share requires cache=none mount option

## Connection to Real Hardware
This same cycle applies to BeagleBone Black AM335x:
- UART0 base = 0x44E09000 (from TRM spruh73q.pdf)
- interrupts = <72> (from TRM interrupt table)
- Verified against linux-6.6/arch/arm/boot/dts/ti/omap/am33xx-l4.dtsi

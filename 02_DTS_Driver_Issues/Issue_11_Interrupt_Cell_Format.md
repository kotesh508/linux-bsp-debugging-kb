# Issue 11 — Wrong interrupt-cells format causes probe deferral

## Problem
interrupt-parent phandle not resolved → probe deferred forever

## Root Cause
Different interrupt controllers require different #interrupt-cells:
- GIC (ARM generic):  interrupts = <type number flags>  (3 cells)
- AM33xx INTC:        interrupts = <number>              (1 cell)

## How to find correct format
1. Open TRM interrupt table → find IRQ number
2. Check interrupt controller node → read #interrupt-cells
3. Match format to cell count

## Verified from
- AM335x TRM spruh73q.pdf Section 6.3 → UART0 IRQ = 72
- linux-6.6/arch/arm/boot/dts/ti/omap/am33xx-l4.dtsi → interrupts = <72>

## Key learning
Always read #interrupt-cells from interrupt-controller node
before writing interrupts property in device node.

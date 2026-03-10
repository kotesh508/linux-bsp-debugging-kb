📘 PHASE 1 — Boot Issues 1–10 (Master Foundation)

We will fully document each like this:

For every issue:

Symptom (log snippet)

Stage identification

What I checked

Root cause

Fix

Interview explanation (2–3 lines)

🟥 Boot Issues 1–10 List

No console output (console= wrong)

Earlycon missing

Wrong kernel image format

Wrong load address

DTB not passed

Wrong root= parameter

Filesystem driver as module

Block driver missing

No init found

Kernel auto-reboot on panic

We will reproduce at least 4–5 in QEMU.

📘 PHASE 2 — DTS + Driver Issues (10 Cases)

Compatible mismatch

Missing clock

Missing regulator

Wrong interrupt number

Wrong memory region

Disabled node (status = "disabled")

Probe deferral case

Missing CONFIG_OF

Device present but driver not enabled

Multiple matching drivers conflict

You already started this with dummy driver — good progress.

📘 PHASE 3 — Panic Analysis (10 Cases)

NULL pointer dereference

Stack overflow

Use-after-free

Bad memory mapping

Invalid IRQ handler

Divide by zero in driver

Infinite recursion

Corrupt module load

Slab corruption

Deadlock causing soft lockup

We will learn to read call trace properly.

🧠 Discipline Rule From Now

We do:

One issue
Break it
Fix it
Document it
Explain it

Then move to next.

No skipping.

# Boot Issue 01 – No Console Output

## 🧭 Objective
Simulate a boot scenario where the kernel runs but no logs are visible on the console.

---

## 🖥 Environment
- Machine: qemuarm64
- Kernel Version: 5.15 (Yocto build)
- Boot Method: QEMU
- Date Tested: 2026-02-21

---

## 🔥 How I Reproduced the Issue

Modified QEMU boot command by removing console parameter:

Working:

-append "console=ttyAMA0 root=/dev/vda rw"


Broken:

-append "root=/dev/vda rw"


---

## 👀 Observed Behavior

- No kernel logs displayed
- System appeared to hang
- No visible panic message

---

## 🧠 Debugging Steps

1. Verified kernel image was loading.
2. Confirmed root filesystem parameter was correct.
3. Suspected missing console output.
4. Compared working vs broken boot command.
5. Identified missing `console=ttyAMA0`.

---

## 🎯 Root Cause

The kernel was executing normally, but no console device was specified.  
Without a console parameter, kernel logs were not routed to UART (ttyAMA0).

---

## ✅ Fix Applied

Restored console parameter:

-append "console=ttyAMA0 root=/dev/vda rw"


---

## 🔎 Verification

- Kernel logs appeared immediately.
- System booted normally.
- Login prompt visible.

---

## 📘 Learning Outcome

- Kernel may run even when no logs are visible.
- Always verify console parameter during early boot debugging.
- Log visibility issues are not always kernel crashes.

---

## 🗣 Interview Explanation (Short Version)

The kernel was running, but the console parameter was missing, so logs were not visible. 
Adding `console=ttyAMA0` restored log output and confirmed the system was booting correctly.

---

## 🗣 Interview Explanation (Detailed Version)

During boot, the kernel executed successfully, but no logs were visible. I verified that the root filesystem parameter was correct and then compared boot arguments.
I discovered that the console parameter was missing, preventing the kernel from routing logs to the UART. After restoring `console=ttyAMA0`, logs appeared and the system booted normally.

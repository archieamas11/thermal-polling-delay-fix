
# 🔥 Virtual Skin Polling Delay Fix for Pixel 7 Pro

*Because waiting 5 minutes to realize you're on fire is a terrible strategy.*

## 🤔 The Problem: Google's 5-Minute Thermal Blindspot

This module addresses a specific, quirky behavior in the Pixel 7 Pro's thermal management engine: **Virtual Skin polling delay**.

By default, the `PollingDelay` for **VIRTUAL-SKIN** is set to **300000ms** (5 minutes).

### What does that actually mean for your hand?
It means Google's primary thermal sensor logic for the *exterior* of the phone (the "skin" temperature) only wakes up to check the temperature **once every five minutes**.

On the Pixel 7 Pro, when you launch a heavy game, switch to 4K video recording, or hammer the 5G modem, the CPU generates a sudden burst of heat. Because the Virtual Skin poller is napping for 5 minutes, **it cannot issue throttling commands quickly enough.** The result? The device feels like it's melting in your hand *before* the software even realizes there's an issue.

### 🕵️ Why Did Google Do This? (Theories)
I don't have a seat at the Google engineering table, but here's my educated guess based on device behavior:

1.  **The Benchmark Shenanigans Theory:** Most industry benchmarks run in short bursts of 2-4 minutes. If you throttle the CPU during a benchmark, the score drops. A 5-minute delay ensures that the device **finishes the benchmark *before* the thermal engine wakes up to ruin the score.** This makes the Pixel 7 Pro look faster in reviews than it might feel in a 30-minute gaming session.
2.  **The Battery Life Theory (Flawed Logic):** It costs less battery to let the CPU sleep longer between sensor checks. However, **heat is the mortal enemy of battery health.** Running a phone at 43°C for 5 minutes because it didn't throttle early causes far more lithium-ion degradation than waking a sensor thread every few seconds would.

It's especially baffling because based on my research, **even Qualcomm's thermal engine typically uses polling intervals around 50ms to 100ms** for their active monitoring zones. So why Google decided to go with a full 5 minutes for the Pixel 7 Pro is honestly beyond me. It's a massive outlier.

## 🔬 How Thermal Management Actually Works

Your phone doesn't throttle off one sensor — it runs a **chain**: raw hardware readings → software estimates → a final decision maker → action.

```
Hardware Thermistors  →  Virtual Sensors  →  VIRTUAL-SKIN  →  Throttle / Cap / Limit
(Real temp readings)     (Usage estimates)    (Final boss)      (The actual slowdown)
```

**VIRTUAL-SKIN** takes the *maximum* of all intermediate sensors to answer: *"How hot does the back glass feel right now?"* — and it's the only thing that triggers user-facing throttling.

**The problem:** Stock config polls this sensor every **5 minutes**. By the time it reacts, your phone is already a hand warmer.

### 🛠️ The Fix: Waking Up The Brain
This module changes the `PollingDelay` value from **300000ms** (5 minutes) down to **5000ms** (5 seconds).

Now, instead of napping for the length of a song, the thermal engine checks in every 5 seconds. This allows it to apply **micro-throttling** (small, almost imperceptible frequency adjustments) the moment heat starts to build, rather than slamming the brakes on the CPU 4 minutes too late.

## 📥 Installation

**Requirements:**
* **Pixel 7 Pro (Cheetah)** - *May work on other pixel 7 series but untested.*
* Root access is required.
* Tested only on **KernelSU Next**.
* Requires **Mountify module**.
* Tested on **Android 16 QPR3 (April Security Patch)**.

**Notes:**

* May also work on **Magisk** or other mount-based modules.
* May work on other Android versions, but not guaranteed.

**Disclaimer:**

* You are responsible for anything that happens to your device.
* This module is provided as-is.
* Test at your own risk.

**Steps:**

1. Flash the module using your root manager (KernelSU / Magisk).
2. Reboot your device.
3. Done.

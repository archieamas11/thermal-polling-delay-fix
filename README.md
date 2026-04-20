# 🔥 Stop your Pixel Devices from being a hand warmer

## The Problem

By default, Google's `PollingDelay` for **VIRTUAL-SKIN** thermal sensor is **300,000ms (5 minutes)**.

When you game or record 4K video, the CPU heats up fast. But the thermal sensor only checks temperature **once every 5 minutes**. Result? Your phone feels like it's melting before software reacts.

## Why Did Google Do This?

I don't have a seat at the Google engineering table, but here's my educated guess based on device behavior:

1. The 5-minute polling delay comes from an Android source commit added to “prevent ADC IRQ issues that could break thermal throttling.” This points to a hardware bug in the Analog-to-Digital Converter (ADC) on early Tensor chips, where frequent polling could cause thermal control failures. However, this likely only affects Tensor G1. The Pixel Tablet, which uses the same Tensor G2 as the Pixel 7 Pro, sets `PollingDelay` to 60000 ms (1 minute) instead of 300000 ms (5 minute). If G2 had the same ADC flaw, it would require the same workaround but it doesn’t. So, the ADC issue was likely fixed starting with Tensor G2, but the 5-minute delay remains as a conservative software fallback.

2. **The Benchmark Shenanigans Theory:** Most industry benchmarks run in short bursts of 2-4 minutes. If you throttle the CPU during a benchmark, the score drops. A 5-minute delay ensures that the device **finishes the benchmark *before* the thermal engine wakes up to ruin the score.** This makes the Pixel 7 Pro look faster in reviews than it might feel in a 30-minute gaming session.

3. **The Battery Life Theory (Flawed Logic):** It costs less battery to let the CPU sleep longer between sensor checks. However, **heat is the mortal enemy of battery health.** Running a phone at 43°C for 5 minutes because it didn't throttle early causes far more lithium-ion degradation than waking a sensor thread every few seconds would.

It's especially baffling because based on my research, **even Qualcomm's thermal engine typically uses polling intervals around 50ms to 100ms** for their active monitoring zones. So why Google decided to go with a full 5 minutes for the Pixel 7 Pro is honestly beyond me. It's a massive outlier.

## The Fix

This module changes `PollingDelay` from **5 minutes → 5 seconds**.

Now the thermal engine applies small, smooth throttling adjustments as heat builds, instead of slamming the brakes minutes too late.

## 📥 Installation

**Requirements:**
- Pixel 7&8 Series — *other Pixel series is not yet supported*
- Root access
- Tested on: KernelSU Next + Mountify module + Stock Android 16 QPR3

**Steps:**
1. Flash the module via KernelSU / Magisk
2. Reboot

**Note:** May work on other Android versions or Magisk, but not guaranteed.

**⚠️ Disclaimer:** Use at your own risk. No warranties.

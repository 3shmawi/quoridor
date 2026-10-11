---
name: sim-check
description: Build the app for the iOS simulator and walk named screens with screenshots. Use when the user says "check on the simulator", "show me", "run it", or /verify needs on-screen proof.
argument-hint: [screens to check]
---

1. **Panel first.** `mcp__Claude_Code_iOS_Simulator__control` `attach`. If nothing is booted: `xcrun simctl list devices available`, boot an iPhone (`xcrun simctl boot <udid>`), attach again.
2. **Build** from the repo root with a long timeout: `fvm flutter build ios --simulator --debug` (add `-t <entry point>` if the screen lives in another `main_*.dart`). Then `launch` with `build/ios/iphonesimulator/Runner.app`.
3. **Driving tips**: pass `duration: 0.15` on taps; `sleep 2–4` before a screenshot after an action; coordinates are in points, screenshots are scaled.
4. **Walk the screens asked for**, screenshot each, and check one key screen again in the other language and dark mode if the app has them.

Report: per screen, what it shows vs. expected, ✅/❌, and any regression found (fix it, test it, rebuild, re-check). Say plainly what could not be checked.

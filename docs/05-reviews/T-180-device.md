# T-180 device tests (TrustedClockHostApi)

Status: NOT YET RUN. Needs real hardware; results to be filled in by the PO or a device-test pass. Do not log or paste clock values into issues beyond the rows below (synthetic test devices only).

How to read a sample: a debug-only temporary button or `flutter run` snippet calling `TrustedClockHostApi().sample()` and showing the three numbers on screen (not in logs). Remove it afterwards.

## Android (real device, minSdk 26+)
1. Sleep under forced Doze: sample S1. Unplug, screen off, `adb shell dumpsys deviceidle force-idle` (or leave idle 15+ min). Wake, sample S2. Pass: |(S2.monotonicMs - S1.monotonicMs) - (S2.wallMs - S1.wallMs)| <= 2000 ms and the idle time was >= 15 min.
2. Reboot: sample S1, `adb reboot`, unlock, sample S2. Pass: S2.bootCount == S1.bootCount + 1 and S2.monotonicMs < S1.monotonicMs.
3. Wall-clock change: sample, change the date forward a day in Settings, sample. Pass: monotonic delta stays small while the wall delta jumps.

## iOS (real device)
1. Sleep: sample S1, lock, leave >= 15 min, sample S2. Pass: |Δmonotonic - Δwall| <= 2000 ms.
2. Reboot: sample S1, reboot, sample S2. Pass: S2.monotonicMs < S1.monotonicMs, bootCount null on both.

## Results
| Test | Device / OS | Result | Date |
|------|-------------|--------|------|
| Android sleep | | pending | |
| Android reboot | | pending | |
| iOS sleep | | pending | |
| iOS reboot | | pending | |

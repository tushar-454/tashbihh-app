# Feature checklist

## Implemented

- [x] Native Flutter/Dart UI; no WebView or backend.
- [x] Complete source audit, repository file hashes and discrepancy log.
- [x] Arabic Bismillah, Tasbih branding, original fonts, exact HSL colors and five gradients.
- [x] Responsive header, compact selector, streak badge, meaning and prayer row.
- [x] Classic rainbow dot counter with original geometry and dot sizes.
- [x] Modern gold arc counter, completion glow and pulse, entry and background transitions.
- [x] All 11 configured Dhikr entries, exact Unicode/meanings/targets/order/eligibility.
- [x] Dua dropdown, persistent per-prayer selection and complete/incomplete indicators.
- [x] Five original prayer labels, Arabic names and emoji.
- [x] Exact config.js fixed local prayer windows; inclusive starts/exclusive ends.
- [x] Automatic active prayer; inactive selection/count blocking; ended-window lock styling.
- [x] Target caps and independent per-prayer/per-Dua counts.
- [x] Independent Custom Mode count/target, 10–1000 step10 control and count clamping.
- [x] Single/double-tap arbitration, custom reset and incomplete-prayer reset; complete protection.
- [x] Exact JavaScript streak completion, daily roll-forward, consecutive/broken/duplicate rules.
- [x] Midnight, resume and restart handling, preserving custom/settings/streak history correctly.
- [x] Native local persistence via storage abstraction and serialized snapshot writes.
- [x] Malformed-data recovery and visible persistence failures.
- [x] Vibration duration 0–100 step5, default40, capability checks and completion pattern.
- [x] App mode, counter style, fullscreen and reset controls with source labels/defaults.
- [x] Source-matched reset confirmation; Cancel/outside dismissal preserves data.
- [x] Full reset restores app defaults and overwrites only this app's own snapshot.
- [x] Mobile SystemChrome, browser and native desktop fullscreen adapters.
- [x] Offline source fonts and fallback fonts/symbols/emoji with licenses.
- [x] Original SVGs plus Android adaptive/legacy, iOS, Web and desktop icon assets.
- [x] Safe areas, landscape scroll fallback and 200% text scaling without overflow.
- [x] Keyboard center activation, screen-reader values/hints/selection and accessible reset action.
- [x] Core native functionality needs no Internet permission or connection.
- [x] Web renderer assets hosted locally and generated offline application cache.
- [x] Source, implementation, missing-assets and validation documentation.

## Verification

- [x] Actual Flutter SDK inspected: Flutter 3.47.9 / Dart 3.13.7, Debian 13.
- [x] `flutter pub get`.
- [x] `dart format .`.
- [x] `flutter analyze`: no issues.
- [x] `flutter test`: 44 tests passed (domain, widget workflows, visual captures).
- [x] Live Chrome source captures at deterministic local times; all major states compared.
- [x] Default, prayer-selected/blocked, Dua menu, partial, complete, custom, both styles, settings, reset, narrow/large/landscape Flutter captures.
- [x] Linux release build and real runtime launch.
- [x] Linux integration-driver workflow: real local storage, reload, fullscreen, counting/reset.
- [x] Android universal release APK built successfully.
- [x] Android emulator integration on emulator-5554: real storage/reload, fullscreen, gestures and confirmed reset; release APK installed and launched.
- [x] Chrome release validation: no JavaScript errors, zero remote requests, correct single/double taps, persisted custom mode/style and offline reload.
- [ ] iOS native build/device testing (requires macOS/Xcode).
- [ ] macOS native build/device testing (requires macOS).
- [ ] Windows native build/device testing (requires Windows).
- [ ] Physical-device vibration feel and hardware intensity equivalence (not testable with emulator).
- [ ] Store distribution signing (user's private production signing credentials required).

The last five unchecked items are platform/distribution validation limits, not missing core features. Final verification results are recorded in implementation-notes.md and docs/validation/.

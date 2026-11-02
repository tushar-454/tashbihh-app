# Implementation notes

## Application

The existing `tashbihh` Flutter starter was replaced with a native Dart/Flutter implementation. The original web checkout was read only. All six existing platform directories remain. No WebView, backend, authentication, telemetry, geolocation, browser-data migration, cloud sync, or import/export was added.

`assets/data/config.json` is a mechanical copy of the complete `window.TASBIH_CONFIG` object, preserving all 11 entries, exact Unicode, IDs, targets, eligible prayers, order and fixed local schedules. `tool/sync_reference.cjs` can refresh these definitions and SVGs from a separate source checkout. The audit records all meaningful differences between JavaScript, documentation and native adaptations.

## Structure

- `lib/app/`: application shell and exact HSL theme tokens.
- `lib/core/config/`: typed prayer and Dhikr configuration loaded from the bundled JSON.
- `lib/core/models/`: daily progress and settings snapshots with defensive loading.
- `lib/core/storage/`: one versioned JSON snapshot in SharedPreferences; storage abstraction for tests. It never reads browser-app storage keys.
- `lib/core/platform/`: conditional native/browser adapters for vibration and fullscreen.
- `lib/features/counter/`: ChangeNotifier controller, clock, interactive screen and CustomPainter rings.
- `lib/features/dhikr/`, `prayer/`, `settings/`, `streak/`: feature widgets and isolated business rules.

All changes save a captured state/settings snapshot through a serialized write queue. Slow earlier writes cannot overwrite a newer count or reset. Failures appear in the UI and a later successful write clears the error. Reset overwrites only this app's own snapshot; it never clears other preferences. A malformed snapshot falls back to usable defaults.

The clock is injectable. The foreground clock checks minute/date changes each second, and every counting/selection interaction and app resume validates time again. Date changes clear prayer counts and completion IDs, retaining the custom count/target, settings, and applicable streak history. Streak day differences preserve JavaScript’s exact floored elapsed milliseconds between local midnights, including the source’s DST quirk: a 23-hour day is0 rather than1. A regression test covers23-hour,25-hour and negative-duration cases.

## Direct dependencies (pinned)

| Dependency | Version | Reason |
|---|---|---|
| Flutter | SDK 3.47.9 used here | Native widgets, painting, animations, lifecycle, mobile system UI |
| shared_preferences | 2.5.6 | Small local snapshot persistence on all six targets |
| vibration | 3.2.1 | Android/iOS capability checks, source duration control and completion pattern |
| window_manager | 0.5.1 | Native Linux/Windows/macOS fullscreen; stable 0.5 API avoids the newly released 0.6 native API migration |
| web | 1.1.2 | Conditional, typed browser fullscreen/vibration; no browser imports in native code |

Development: `flutter_test` and `integration_test` from the SDK, and `flutter_lints` 6.0.0. Transitive versions are locked in `pubspec.lock`. No state-management/router/network/database dependencies are needed. `flutter_svg` is unnecessary: the counter uses CustomPainter, and original SVGs are retained as branding sources and rasterized for launchers.

## Interaction details

Classic dots match the SVG's 320-unit geometry, target-dependent dot radii and rainbow hues. Modern ring uses radius118, stroke16 and a rounded gold arc. Center size, responsive ring size, gradients, Arabic heading, compact Dua dropdown, streak badge, prayer tiles, settings and confirmation copy follow the source. Short windows scroll; the ring stays circular in landscape. SafeArea and native system UI handle display cutouts and navigation. Original emoji are bundled as a tiny font subset. Android launch themes and the iOS launch-screen background use the source manifest color #151a26; Android12+ displays the official launcher icon.

The center uses Flutter's gesture arbitration: a single tap increments once after the double-tap recognition interval, and a double tap resets without an extra increment. A completed prayer Dua cannot be reset this way; Custom Mode can always reset. Background taps also count like the source and allow fast repeated taps. Control taps and menu dismissal do not propagate into counting. Keyboard Enter/Space activates the center. Screen readers receive count/target and blocked hints, and an explicit Reset counter custom action where eligible; accessibility activation counts once rather than treating the assistive technology's activation gesture as a reset.

Automatic active-prayer selection and disabling other prayer buttons occur only in Prayer Mode during an open window. Custom Mode deliberately retains the prayer theme and selected Dua text, exactly like the source. The displayed custom target is independent; the Dua checkmark still reports prayer completion. Changing mode does not copy counts between modes.

## Run and build

From the project root:

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter run -d emulator-5554
flutter run -d chrome
flutter run -d linux
flutter build apk --release
flutter build linux --release
```

For a self-contained offline Web release:

```sh
flutter build web --release
python3 tool/prepare_web_offline.py
python3 -m http.server 8765 --directory build/web
```

The bootstrap uses local `canvaskit/`; the post-build script creates a versioned service worker caching the full build, fonts and renderer. Serve Web via HTTPS or localhost, wait for initial cache installation, then offline reload works. This cache step must be rerun after every Web build. `flutter run -d chrome` is a development server and does not install this production offline cache. Native installations are offline immediately and have no Internet permission in the Android release manifest.

Outputs: `build/app/outputs/flutter-apk/app-release.apk`, `build/web/`, `build/linux/x64/release/bundle/`. Copy the entire Linux bundle, including `data` and `lib`, when distributing it.

Gradle is limited to a 2GB heap/two workers so it can build alongside an emulator on this 16GB development machine. Existing application IDs and toolchain settings are retained. Android release currently uses the starter's **debug signing key**: it is an installable release-mode APK, not a store-signed release. Configure a private release keystore and final application/bundle identifiers before store publication. No production signing key was generated or committed.

## Platform limits

- Android/iOS vibration duration and strength depend on hardware and OS. This is the source's millisecond duration setting, not a promise of identical physical amplitude. The completion pattern is preserved where supported. A simulator cannot verify physical feedback.
- Browsers may reject vibration/fullscreen; adapters catch unsupported/blocked requests. Desktop vibration is gracefully disabled. Fullscreen is session state, like the source, rather than a stored preference.
- Android/iOS fullscreen uses SystemChrome immersive/edge-to-edge modes. Current OS policies and safe areas may retain system affordances. Desktop uses native window fullscreen; Web uses the browser Fullscreen API.
- iOS, Windows and macOS folders/icons/source are prepared but cannot be built or device-tested from Debian. Apple distribution also requires signing on macOS.
- Emoji, font rasterization, system dialogs and fullscreen affordances can differ slightly across engines and OS versions. The core geometry, source text and colors are retained.

## Tests and visual evidence

See `feature-checklist.md` and `docs/validation/` for final verified status and screenshots. The domain tests exercise complete successful prayer days, consecutive/broken/duplicate streaks, local boundaries, inactive selection, midnight/restart, target caps, custom state, sanitization, serialized writes and reset. Widget tests exercise actual taps, double taps, selectors, settings, confirmation and viewport/text-scale changes. Visual-capture tests load the real offline fonts and capture every major screen state.

`integration_test/app_test.dart` uses real platform storage and fullscreen, rebuilds the controller/widget tree from disk, checks Custom Mode and reset, and captures Android screens through `test_driver/integration_test.dart`. This test resets only the app's own test-installed snapshot. Commands:

```sh
flutter drive -d linux --driver test_driver/integration_test.dart --target integration_test/app_test.dart
flutter drive -d emulator-5554 --driver test_driver/integration_test.dart --target integration_test/app_test.dart
```

The first Linux `flutter test ... -d linux` runner attempt terminated with a stream-channel shutdown error. The integration-driver route completed successfully and is the documented Linux verification command. Linux fullscreen produced a temporary OpenGL resize warning while switching display sizes; the workflow and fullscreen checks passed.

Optional reference/browser tooling uses Node and Playwright. Install Playwright separately or set `PLAYWRIGHT_MODULE` to its module path; set `CHROME_BIN` if Chrome is not `/usr/bin/google-chrome`. Run source captures with `tool/capture_source_states.cjs`; use `tool/generate_icons.cjs` to regenerate launcher rasters. Font subsetting used fontTools against the licensed system Noto Emoji and DejaVu files. These tools are not runtime dependencies.

## Actual verification results — 2 November 2026

| Check | Result |
|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7, Debian 13 Linux |
| `flutter pub get` | Passed |
| `dart format .` | Passed; 24 Dart files formatted |
| `flutter analyze` | Passed; no issues |
| `flutter test` | Passed; 44 tests; the 32 domain tests also passed with TZ=America/New_York |
| Android release build | Passed; universal APK at `build/app/outputs/flutter-apk/app-release.apk` (approximately 50.7 MB) |
| Android emulator | Integration-driver scenario passed on emulator-5554, API 37; real storage reload, styles/modes, fullscreen, gesture arbitration and reset confirmed |
| Release APK install/run | Installed with ADB and launched MainActivity on emulator-5554 |
| Linux release build | Passed; complete desktop bundle generated |
| Linux native integration | Driver scenario passed with real preferences and native fullscreen |
| Flutter Web release | Passed; local renderer/fonts and 50-file versioned offline cache generated |
| Chrome runtime | Passed; zero JS errors, zero remote requests, single tap1, double tap0, offline reload restored Custom/Modern/count0 |
| Visual inspection | Eleven deterministic live-source states and twelve Flutter states captured; native Android and actual Chrome screenshots inspected |
| Android release permissions | VIBRATE plus generated package-internal receiver permission; no Internet permission |
| iOS / macOS / Windows | Source and icons prepared; native builds/device tests unverified on Debian |

After the passing native integration runs, the emulator disconnected under host load. With compilation stopped and the idle build daemon released, it was restarted successfully. The **exact final APK** was then installed and cold-launched successfully (`Status: ok`, `LaunchState: COLD`), and its screen captured directly. The 44-test suite, the 32-test New York timezone run, and all three release builds include the final source-exact streak helper.

The emulator used software graphics and a 2 GB RAM allocation while running alongside desktop applications and builds. It logged slow-frame warnings and once showed an Android **System UI** timeout under host resource pressure. The app's native integration scenario completed successfully; emulator timings do not establish physical-device performance. The initial 8 GB Gradle setting was reduced to 2 GB/two workers to stabilize builds. A Web compiler attempt was terminated during concurrent heavy workloads; a later independent release build and the final Chrome checks passed.

Flutter Web's icon tree-shaker reports a CupertinoIcons-family warning from framework defaults. This app uses bundled Material icons, exact source emoji/symbols and original SVG launcher artwork; the Chrome no-external-request check passes and no rendered app asset is missing. No Cupertino icon package was added solely to silence an unused framework-family warning.

See `docs/validation/chrome-results.json`, `verification.json`, the screenshot comparison table and captured native screens for evidence. Android integration screenshots may include the test runner's pointer marker; `android-release.png` is a direct emulator capture of the installed release.

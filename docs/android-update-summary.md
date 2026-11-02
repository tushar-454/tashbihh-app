# Android update summary

## Implemented

- Existing Settings panel now offers Export Backup and Import Backup with matching button/theme styling, descriptions, loading, a validated restore preview, explicit replacement warning/confirmation, and success/error feedback.
- Complete schema-versioned UTF-8 state backups include every saved prayer/Dhikr count and completion, daily date, selected prayer/Dhikr, streak/last successful date, Custom Mode progress/target, mode, counter style, and vibration setting.
- Kotlin Storage Access Framework integration uses ACTION_CREATE_DOCUMENT/ACTION_OPEN_DOCUMENT and content resolver streams on an I/O executor. Imports are bounded to 1 MiB on both sides. Export success follows stream closure. No broad storage permissions or app-private export-only path.
- Restore validates before changing anything, waits for queued saves, blocks mutations during commit, writes the existing single snapshot key, attempts rollback on write failure, and updates live models only after success. Historical imports retain their original dated prayer/streak record and follow existing daily rollover rules.
- Central PrayerSchedule resolves active prayer, per-prayer eligibility, effective ends and next transitions. Every increment checks a fresh injectable local clock. Android clock/date/timezone broadcasts, lifecycle refresh, boundary scheduling and a one-minute foreground watchdog keep the UI current.
- Original app identity, package ID, icons, theme, counter styles/animations, selection restrictions, Custom Mode, private storage key/version, and streak semantics are retained.

## Schedule

| Prayer | Local start (inclusive) | Local end (exclusive) |
|---|---|---|
| Fajr | 04:45 | 06:00 |
| Dhuhr | 12:00 | 15:00 |
| Asr | 16:45 | 18:00 |
| Maghrib | 18:45 | 20:00 |
| Isha | 20:30 | 22:00 |

These are the actual Flutter configuration and original config.js times. `prayerEndGraceMinutes` is centralized and defaults to **0** to preserve intentional gaps and original end restrictions. Configurations may explicitly opt into 0–180 minutes of end grace, always capped by the next start or midnight. There is no early-start buffer or automatic gap filling. See [prayer availability](prayer-availability.md).

## Files changed or added

| Area | Files |
|---|---|
| Backup validation/serialization | `lib/core/backup/backup_service.dart` (new) |
| Android document API | `lib/core/platform/backup_documents.dart` (new), `android/app/src/main/kotlin/com/example/tashbihh/MainActivity.kt` |
| Shared schedule/configuration | `lib/core/time/prayer_schedule.dart` (new), `lib/core/config/tasbih_config.dart`, `assets/data/config.json` |
| State and commit/recovery | `lib/core/models/app_state.dart`, `lib/core/storage/progress_repository.dart`, `lib/features/counter/counter_controller.dart` |
| Clock event abstraction | `lib/core/platform/device_services.dart`, `lib/core/platform/services_native.dart` |
| Existing UI | `lib/features/counter/counter_screen.dart`, `lib/features/settings/settings_panel.dart`, `lib/features/prayer/prayer_selector.dart` |
| Tests | `test/backup_test.dart`, `test/backup_workflow_test.dart`, `test/prayer_availability_test.dart` (new), `test/test_support.dart` |
| Documentation | `docs/backup-restore.md`, `docs/prayer-availability.md`, this file |
| Validation evidence | Updated affected existing `docs/validation/flutter-*.png` captures; new logs, synthetic round-trip JSON and emulator screenshots under `docs/validation/upgrade/` |

## Dependencies and compatibility

**No dependencies added.** Existing shared_preferences persists the single snapshot. Native Android APIs and Flutter MethodChannel/EventChannel handle files and clock events. `pubspec.yaml`, lockfile, manifests, Gradle application ID and signing configuration are unchanged. Existing key `tasbih.native.snapshot.v1` and snapshot version 1 remain valid; the optional historical restore record is additive.

## Verification

Using installed Flutter **3.47.9**, Dart **3.13.7**:

| Check | Result |
|---|---|
| `flutter pub get` | Passed |
| `dart format .` | Passed |
| `flutter analyze` | Passed, no issues |
| `flutter test` | **92 passed**, zero failures |
| `TZ=America/New_York flutter test test/domain_test.dart test/prayer_availability_test.dart test/backup_test.dart` | **70 passed**, zero failures |
| `flutter build apk --release` (final sequential run) | Passed, 17.3 seconds, 51.5 MB |
| Actual Android Files + uninstall/reinstall + cold restart round trip | Passed on fresh API 37 emulator |
| Actual Android clock/timezone/resume/midnight/Custom Mode checks | Passed on fresh API 37 emulator |
| APK package/permission inspection | `com.example.tashbihh`, min API 24, target API 36, no storage or internet permission |

New tests cover complete exports/settings/streak round trips, empty-install recovery, historical dates, malformed/oversized/unsupported backups, inconsistent completion metadata, mutation isolation, permanent write failure, rollback after a reported post-write failure, confirmation/picker cancellation, success/error handling and loading, stale taps, fake clock jumps, every schedule boundary and every civil second under multiple grace policies, gap behavior, overlapping configuration, midnight, lifecycle and clock event UI updates.

Earlier verification found and fixed a missing test clock-stream abstraction, test setup waiting outside Flutter's fake event loop, and the preview's unnecessary animated loading indicator. One intermediate build failed when concurrent Flutter test/build commands rewrote GeneratedPluginRegistrant; the final build ran sequentially after all tests and passed. No failed check has been treated as passing.

## APK

`build/app/outputs/flutter-apk/app-release.apk`

SHA-256: `bc91351e613bbe20cfdb6179cf9334109b876125b997f62517321e243b1bb221`

This is a release-mode APK using the project's existing **debug signing configuration**. Publishing requires the project's production signing setup and appropriate versioning, which this task does not change. No commits or pushes were made.

## Device acceptance and limitations

Android acceptance results are recorded in `docs/validation/upgrade/android-backup-acceptance.txt`. A dedicated fresh API 37 emulator was created under ignored `build/tasbih-e2e-avds`; existing devices/AVDs and real user data were not used. The system Files provider was exercised through actual on-device UI automation.

The actual system-provider flow passed: complete test progress for all five prayers (three completed Dhikr each), streak 4 and successful date, Custom Mode 13/240, modern style and vibration 75ms were exported to Downloads. The JSON remained after uninstall. Reinstall started with empty data; selecting the saved JSON and confirming recovered the full state. Cold restart and a second export produced equivalent `data` objects. Actual confirmation cancellation also preserved the initial settings. The complete comparison is in `device-roundtrip.json` and UI evidence in `android-*.png`.

Actual prayer acceptance also passed on the emulator: each canonical start enabled its prayer and accepted a tap; a move into an inactive gap blocked another tap; changing timezone to America/Los_Angeles and back to UTC immediately refreshed availability; resuming after a clock change selected Isha; remaining open through midnight reset daily counts; and Custom Mode accepted a count during the inactive midnight interval. Device time/timezone/automatic settings were restored afterward, and the isolated emulator was shut down. Details are in `android-prayer-acceptance.txt`.

The UI automation initially needed adjustment for Android's uppercase `SAVE` button label; the raw log includes that harness retry followed by the successful continuation. The emulator also briefly reported startup System UI delays; those were resolved before acceptance. These were not recorded as application test passes.

Real Google Drive/removable-storage providers and physical OEM devices still need acceptance testing. Provider persistence/upload outside successful stream closure is outside the application's control. Android may interrupt a pending picker on process death; retry the operation. Severe storage/hardware failure can also prevent rollback; that reports failure and never restore success.

The app remains an offline local-file system, without automatic cloud backup or migration. The historical record stores the last historical restore, not a new daily history UI. Normal missed-day streak expiry and the original DST consecutive-day quirk remain intentional compatibility behavior. See [backup and restore](backup-restore.md) for schema, date rules and recovery instructions.

# Notification implementation verification

Executed locally on 2026-11-04 with Flutter 3.47.9 / Dart 3.13.7,
Android compile/target SDK 36, min SDK 24, AGP 9.1.0.

| Command/check | Result |
| --- | --- |
| `flutter pub get` | Passed; lockfile unchanged; no new Flutter runtime dependencies |
| `dart format` on the eight changed/new Dart files | Passed; final verification changed zero files |
| `flutter analyze` | Passed; no issues |
| `flutter test --no-pub` | Passed; 230 tests (217 existing + 13 notification/setting tests) |
| `cd android && ./gradlew :app:testDebugUnitTest --console=plain` | Passed; 53 tests, zero failures/errors |
| `cd android && ./gradlew :app:lintDebug --console=plain` | Passed; zero errors, 15 warnings |
| `python3 -m unittest discover -s tool/tests -v` | Passed; 46 release-automation tests |
| `flutter build apk --release` with a disposable validation signing environment | Passed; final build 185.4 seconds |
| `apksigner verify --verbose --print-certs` | Passed; certificate matches the generated validation key |
| `aapt2 dump badging` / `aapt2 dump xmltree --file AndroidManifest.xml` | Passed; package/release/ABIs/permissions/receiver inspected |
| Receiver DEX class, exported=false, allowBackup=false, no USE_EXACT_ALARM | Passed |
| `git diff --check` | Passed |

Native reports: com.example.tashbihh.PrayerNotificationPolicyTest: 11, com.example.tashbihh.PrayerNotificationsTest: 42.
The receiver/storage tests run under Robolectric SDK 33 and 34 (Android 13/14).
They simulate permissions, alarms and OS notifications; they are not physical
Android delivery tests. Policy tests use fixed clocks. Native storage/receiver
entry points accept explicit test instants, and Dart tests use fixed dates and
mocked platform channels. No test requires GPS, a real account, or a network
prayer-time request.

Lint warnings comprise Android KTX style suggestions, newer Gradle/test-library
versions, and existing backup/resource configuration. The API 24-25 settings
compatibility warnings found during review were fixed and are absent in the
final report. Kotlin/Gradle retain SDK compatibility/deprecation notices; Dart
analysis has no issues.

## Artifact

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 54,852,164 bytes
- SHA-256: `fe078bc32d4f903211941d2ef2744b8ec81ca06960a61d8c93389464fbd21cad`
- Includes armeabi-v7a, arm64-v8a and x86_64 AOT libraries.
- Not debuggable; package `com.example.tashbihh`; version 1.0.0 / code 1.
- **Signed with a temporary local validation certificate, not production-signed.**
- Certificate fingerprint/signature output: `apk-signature.txt`.
- Packaged manifest and metadata: `apk-manifest.txt`, `apk-badging.txt`.
- Temporary private signing key deleted after successful verification.
- Production signing properties, credentials, and GitHub Actions workflows unchanged.
- No commit, push, publication or GitHub release was performed.

## Review fixes

- UTC/GMT aliases in the timezone database.
- Midnight-reset Isha and previous-date summary archive semantics.
- Drop invalid short-window offsets and expired reminders.
- Preserve an after-midnight summary beyond the final plan date.
- Clear obsolete summary history during restore/reset/account replacement.
- Persist duplicate suppression and enforce eleven actual deliveries per local day.
- Keep an inexact backup when exact access is revoked without a broadcast.
- Explicit API 24-25 fallback for the settings shortcut.
- Avoid Flutter interpreting notification tap intent URIs as deep-link routes.
- Wire Flutter assets into AGP 9 resource-enabled native host tests.

## Remaining acceptance work

No physical Android device was connected. An isolated API 37 emulator was
attempted under `/tmp`; without `/dev/kvm` it stayed offline and was stopped.
Actual foreground/background/terminated-app delivery, native permission dialog
UI, physical reboot/update behavior, Doze/OEM battery policies and live tap
navigation remain unverified on a device. Robolectric coverage does not remove
these acceptance requirements.

See [feature behavior and phone acceptance steps](../../smart-prayer-notifications.md).
The seven-day horizon, timezone-change pause until foreground, Android force-stop
restrictions, OS delays, and commit-before-post crash tradeoff are documented there.

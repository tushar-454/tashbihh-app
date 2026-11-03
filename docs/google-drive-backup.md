# Android Google Drive backup and reset

## Repository audit and data scope

The existing architecture is a `CounterController` with a serialized write queue,
`ProgressRepository` with one SharedPreferences snapshot (`tasbih.native.snapshot.v1`),
and a strictly validated JSON `BackupSerializer`. Settings previously called the
native JSON document picker through Export/Import. Those UI actions are replaced
by one **Backup/Restore** button. The JSON serializer and legacy document bridge
remain available internally; there is no unrelated platform refactor.

Backup payloads reuse the complete existing JSON export:

- Each prayer's selected Dhikr, independent counts, and completion records.
- Selected prayer, progress date, streak, last successful streak date, and the
  original dated prayer record retained by a historical restore.
- Custom count and target.
- Vibration intensity, prayer/custom mode, and classic/modern counter style.

As before, resetting user data returns those values to their initial defaults.
Prayer schedule cache, prayer-time location/permission bookkeeping, bundled
configuration, fullscreen/device state, and runtime prayer synchronization are
independent and preserved. Location coordinates, Google account identity,
authentication credentials, and synchronization bookkeeping are never included in
cloud payloads. The account ID/email and sync metadata live only in the local
snapshot's separate `cloud` object. Old version-1 local snapshots still load.

## Architecture

`CloudBackupCoordinator` exclusively owns connection/switch, upload, scheduled
eligibility, and reset. Overlapping requests fail rather than waiting in a queue
with stale account state. `BackupAuth`, `BackupDrive`, and `BackupScheduler` are
injected interfaces used by automated tests.

`GoogleBackupAuth` uses `google_sign_in` 7.2.0, Android Credential Manager, and
account-specific authorization clients. It supplies the configured web client ID
as `serverClientId` and requests only `https://www.googleapis.com/auth/drive.appdata`.
A picker transition signs out of the SDK picker session without revoking access;
the committed app account stays unchanged until the operation succeeds. Known
account objects are retained in memory so a failed switch can still authorize the
previous account. After a process restart, session recovery may require the user
to authenticate the committed account again. Unexpected identities are rejected
before any Drive mutation.

`GoogleBackupDrive` uses the existing `http` dependency with Drive REST v3. It
searches only `appDataFolder`, exact filename `tasbihh_backup.json`, non-trashed
files, and the private parent. It updates the discovered file with PATCH and
creates a multipart file only when absent. An additional absence check refuses to
overwrite a file that appeared during first connection. Pagination is handled;
incomplete searches fail safely. If legacy duplicates exist, the latest modified
file is authoritative and subsequent uploads update it. Reset deletes all exact
matches for this app inside the current account's private app-data folder.

`CloudBackupFormat` wraps the existing versioned JSON in an outer version-1
envelope containing a UTC creation timestamp, base64 payload, and SHA-256 payload
checksum. Both envelope and inner schema are validated before committing. Inner
payloads are limited to 1 MiB and outer downloads to 2 MiB, including during stream
consumption. The checksum detects accidental corruption; it is not a digital
signature or encryption. Access and refresh tokens are never written to disk or
the backup. Access tokens remain in the authorization/session objects in memory.

## Connection, switching, and immediate backup

An unconnected tap opens the Google picker and requests Drive authorization.
An existing valid backup is automatically restored as authoritative. Otherwise
current local progress is retained and immediately backed up (Option A).
Corrupt, future-dated, incompatible, unavailable, or unauthorized backups abort
connection without modifying local progress or the committed account.

A connected tap captures current progress and uploads immediately, even when
unchanged. It then shows the current account, result, and **Switch Google
account**. Switching runs the same restore-first
transition for the newly selected account. No old data is uploaded to that
account before checking its existing backup. The previous committed identity and
progress survive cancellation or failure.

Restore and reset freeze user-data mutations during the transition. Ordinary
network uploads leave counting available. Each upload captures its snapshot and
pending event revisions together; later changes are included on the next trigger.
Metadata writes serialize against outstanding progress writes without freezing counter
interactions; subsequent count writes retain the committed metadata.

`CounterController.commitCloud` stages the new state/settings and writes the
progress plus account metadata together using the existing single-key replacement
and rollback mechanism. Live controller state changes only after the write
succeeds. A restart consequently loads the previous snapshot or the new snapshot,
with account identity and progress in the same commit unit. A storage failure
whose rollback cannot be verified is reported as a failure; it is never reported
as a successful restore or reset.

Historical prayer progress follows existing daily rollover rules, rather than
assigning yesterday's prayer counts to today. The dated history is retained in
`restoredDay`; custom progress and settings are restored normally.

## Event-based backups

There is no twice-daily schedule, 12-hour eligibility check, periodic retry timer,
or upload caused solely by elapsed time. Once Google Drive is connected, uploads
are triggered by:

1. **Closing or backgrounding the app:** the first `hidden`, `paused`, or
   `detached` lifecycle event after a foreground session requests one immediate
   upload, even if data is unchanged. Repeated lifecycle events for that close
   are deduplicated. A temporary `inactive` focus change does not request a
   backup, and disposing the screen does not simulate a close.
2. **Tapping Backup/Restore while connected:** one immediate upload to the
   currently committed Google account. First connection and account switching
   keep their existing restore-first behavior, creating a first backup only
   when the selected account has none.
3. **Losing an existing streak:** completing at least three duas in every
   prayer earns a streak day. An unfinished day drops an existing streak to zero
   at the next local midnight, or when the app next observes the new date. This
   requests one immediate upload of the full reset snapshot. A successful day's
   ordinary rollover does not request an extra backup. A historical restore that
   drops an old streak to zero follows the same rule.
4. **Earning a streak day:** when the final required dua completes and all five
   prayers have at least three completed duas, the streak increases once for that
   local date and requests one immediate full backup. This normally happens on
   Isha's third completed dua when the earlier prayers already qualify. Additional
   duas, refreshes, and same-day restores do not award another day or request
   another earned-streak backup.

At startup/resume, daily rollover compares the saved progress date with today's
local date. An existing streak survives only when the saved day was successful
(`lastStreakDate` equals the saved progress date) and today is exactly the next
local day. An incomplete saved day or skipped day resets it to zero, clears the
daily prayer progress, and requests the reset backup once. Opening the app the
morning after a successful day preserves the streak until that new day's
requirements are evaluated.

The reset snapshot includes the current date, cleared prayer counts/completions/
selections, and zero streak. Custom progress, settings, and last successful streak
date are retained. The backup always contains all current progress and settings.

Close, streak-loss, and earned-streak requests are persisted as
`closeBackupPending`, `dailyResetPending`, and `streakEarnedPending` inside the
local progress snapshot. Only a successful upload of the matching captured
revision acknowledges a request. A new close or streak
change during an older upload or native metadata commit remains pending for an
immediate follow-up upload of the latest state. If multiple events are covered by
one snapshot, that single upload acknowledges them together.

Failed uploads keep their event markers and successful timestamps. There is no
automatic retry loop: pending work retries on the next startup/resume, a new
close, or an explicit Backup/Restore tap. An ordinary startup/resume without
pending work does not upload. Account changes and Reset Everything remain
serialized; interrupted Reset Everything blocks all backup recreation.

Close-time uploads use noninteractive authorization and start immediately as the
app leaves the foreground. They do not delay Android's system exit and are best
effort: Android can suspend or kill the process before a request finishes, and a
force-stop may provide no lifecycle callback. Persisted requests recover on the
next launch when the local write completed. See Flutter's
[application lifecycle guarantees](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html).
There is no headless worker or background scheduling service. Expired Google
authorization requires a foreground Backup/Restore tap; automatic backups never
open a consent dialog.

## Reset Everything

The existing reset entry has exactly two confirmation actions, **Cancel** and
**Reset Everything**. The connected dialog explicitly explains permanent local
and Google Drive deletion. An unconnected dialog describes local deletion only.
Nothing is deleted on cancellation or dismissal.

After confirmation the coordinator blocks other operations and durably saves
`resetPending` before touching the remote file. It then authorizes the currently
committed account, deletes only this app's exact
backup matches, verifies each file is missing (404), and verifies the final search
is empty. An already missing backup is success. Only then are progress/settings
replaced with defaults and cloud account/sync metadata cleared in one commit.
There is no SDK revocation or deletion of another account's backup.

Offline, expired authorization, denied access, unconfirmed deletion, and local
storage failures are reported without claiming success. Local progress stays
active if deletion or the subsequent local commit fails. The persisted pending
reset marker prevents stale data from recreating the backup, even after process
termination between remote deletion and local clearing. The user can keep using
counters and explicitly retry Reset Everything. While reset is pending, new
connections and backups remain blocked. A successful reset disconnects cloud
backup at the app level and requires explicit setup before another upload.

Android OS Auto Backup is disabled (`android:allowBackup="false"`) to avoid
restoring stale account/progress snapshots outside the explicit recovery/reset
flow. No unrelated platform configuration is changed.

## Dependencies and Android configuration

New direct dependencies: `google_sign_in: ^7.2.0` and `crypto: ^3.0.8`.
Drive uses the existing `http: 1.6.0`; no Firebase, Google API client package,
backend, client secret, service account, or paid service is required.

The Android package/namespace remain `com.example.tashbihh`. INTERNET permission
and Flutter plugin loading were already configured. No google-services Gradle
plugin or google-services.json is needed when passing the supplied web client ID.
The built debug APK's signing certificate was verified with `apksigner` and matches
`A6:44:8E:B8:CB:A2:78:17:B3:C4:83:70:59:E3:66:65:4D:23:43:8D`.
Any future production signing certificate must also be registered in Google Cloud.

Reference documentation: [Android Sign-In setup](https://pub.dev/packages/google_sign_in_android),
[scoped account authorization](https://pub.dev/documentation/google_sign_in/latest/google_sign_in/GoogleSignInAuthorizationClient-class.html),
[Drive private app data](https://developers.google.com/workspace/drive/api/guides/appdata),
[Drive uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads).

## Automated and manual verification

Automated tests inject authentication, Drive storage, local storage, and lifecycle events.
HTTP transport tests use `http/testing.dart` and never reach live Google APIs.
Coverage includes first connection, automatic authoritative restore, Option A,
immediate manual/close/streak-loss/earned-streak uploads, lifecycle deduplication, no periodic
uploads, pending event recovery, concurrent event revisions, account switching,
mismatched identities, corrupt
checksums/versions, authentication failure, concurrent operations, reset cancel,
cloud/local reset, already missing files, deletion failure, failed local commit,
interrupted reset recovery, and prevention of post-reset backup recreation.
Existing serializer/rollback tests and prayer/counter regressions remain enabled.

Required real Android checks (not exercised against a live Google account here):

1. Choose the configured OAuth test account; grant/deny/cancel Drive consent.
2. Connect an empty account with nonzero progress; verify first backup and later
   in-place updates. Reinstall and connect to restore prayer/custom/settings data.
3. Switch between two accounts with different backups and to an empty account;
   cancel a switch and verify subsequent uploads still use the committed account.
4. Test network loss, revoked permission, and expired authorization, including
   reconnecting the committed identity after process death.
5. Change progress, background or close the app, and verify one latest backup
   per close. Test Home, Back, app switching, offline close, and next-launch
   recovery. Complete Isha's third dua after every earlier prayer meets the
   minimum and verify one backup with the increased streak. Lose a streak in a
   debug fixture and verify one zero-streak backup on rollover/next launch.
   Confirm no scheduled uploads or overlap with account/reset operations.
6. Cancel reset; confirm reset; test offline deletion failure; interrupt after
   remote deletion; restart and explicitly retry. Verify another account's
   backup and unrelated private app-data files survive.
7. Verify TalkBack, large text, picker dismissal, process death during a restore,
   and live prayer synchronization during/after a backup or restore.


## Final verification results

All commands completed successfully on November 3, 2026:

| Verification | Result | Evidence |
| --- | --- | --- |
| `flutter pub get` | Passed | [Dependency log](validation/cloud-backup/pub-get.txt) |
| `flutter analyze` | No issues | [Analysis log](validation/cloud-backup/analyze.txt) |
| `flutter test` | 193 tests passed | [Complete suite log](validation/cloud-backup/flutter-test.txt) |
| `flutter build apk --debug` | Passed | [Build log](validation/cloud-backup/android-debug-build.txt) |
| APK signing certificate | Matches supplied SHA-1 | [Signature verification](validation/cloud-backup/apk-signature.txt) |

APK: `build/app/outputs/flutter-apk/app-debug.apk`.
Gradle emits a Java native-access warning but the build succeeds. No live Google
account or physical Android device was used for these automated checks; the
manual flows above remain to be verified on a device with Google Play services.

## Files changed

| Files | Purpose |
| --- | --- |
| `lib/core/backup/cloud_backup_coordinator.dart` | Serialized cloud operations, account transitions, retries, reset recovery |
| `lib/core/backup/cloud_backup_format.dart` | Versioned checksummed cloud envelope |
| `lib/core/backup/cloud_ports.dart` | Mockable authentication and Drive contracts |
| `lib/core/backup/google_drive_backup.dart` | Google account authorization and Drive REST transport |
| `lib/core/storage/progress_repository.dart` | Account metadata inside the progress snapshot; metadata-safe count writes |
| `lib/features/counter/counter_controller.dart` | Staged atomic restore/reset and nonblocking synchronization metadata commits |
| `lib/features/counter/counter_screen.dart` | Backup account flow, feedback, lifecycle checks, coordinated reset confirmation |
| `lib/features/settings/settings_panel.dart` | One Backup/Restore entry replaces Export/Import |
| `lib/app/app.dart`, `lib/main.dart` | Android-only dependency creation and injection |
| `android/app/src/main/AndroidManifest.xml` | Disable Android OS Auto Backup for explicit recovery semantics |
| `pubspec.yaml`, `pubspec.lock` | Sign-In and checksum dependencies |
| `test/cloud_backup_coordinator_test.dart`, `test/cloud_backup_support.dart` | Coordinator scenarios and injected fakes |
| `test/google_drive_backup_test.dart` | Mock HTTP transport, isolation, update, and verified deletion tests |
| `test/backup_workflow_test.dart`, `test/widget_test.dart` | Settings/confirmation flows and existing counter UI regression tests |
| `README.md`, `docs/google-drive-backup.md` | Usage, audit, architecture, limitations, and manual verification |
| `docs/validation/cloud-backup/*` | Dependency, analysis, test, build, and signing evidence |

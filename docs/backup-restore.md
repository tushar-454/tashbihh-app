# Android backup and restore

Settings → **Backup & Restore** provides Export Backup and Import Backup, within the existing settings panel and theme. There are no new dependencies or storage permissions.

## Export

Export takes a detached JSON snapshot of the current controller state after checking the local date. Unsaved queued taps are included because the snapshot comes from live state. UTF-8 bytes are sent to a focused Kotlin channel (`tasbih/backup_documents`). Android `ACTION_CREATE_DOCUMENT` lets the user choose Downloads, removable storage, or a document provider such as Drive if installed. The suggested name is `tasbih-backup-YYYY-MM-DD-HH-mm.json`. Kotlin writes the selected content URI on an I/O executor, flushes and closes the stream, and only then reports success. Canceling the picker is silent and leaves app data untouched. Provider errors show failure, never success; a provider may leave an incomplete output file after a failed write.

The exported file is outside app-private storage. No internal temporary backup path or broad storage access is used. Fullscreen is session state and is not exported; neither are timers, animation state, storage errors, or caches.

## Schema version 1

```json
{
  "format": "tasbih_backup",
  "schemaVersion": 1,
  "exportedAt": "2026-11-02T09:30:00.000Z",
  "appVersion": "1.0.0",
  "data": {
    "state": {
      "date": "2026-11-02",
      "selectedPrayer": "fajr",
      "prayers": {
        "fajr": {
          "selectedDuaId": "subhanallah",
          "counts": {"subhanallah": 7},
          "completed": []
        }
      },
      "customCount": 12,
      "customTarget": 100,
      "streak": 3,
      "lastStreakDate": "2026-11-01"
    },
    "settings": {
      "vibrationIntensity": 40,
      "mode": "prayer",
      "style": "classic"
    }
  }
}
```

The example abbreviates `prayers`: real files must include **all five configured prayer IDs** and each prayer's selected Dhikr, count map, and completion list. Sparse count maps mean omitted known Dhikr counts are zero, matching the existing app. All saved Dhikr counts are included, including nonselected entries. Completion flags are retained because they participate in the existing streak system. Custom progress, selected prayer/Dhikr, style, mode, and vibration intensity are included. Streak count and last successful date are the entire original app's streak metadata; no additional historical streak log existed.

Export timestamps are UTC ISO 8601 instants with `Z`. Import accepts ISO timestamps with an explicit offset as well. Prayer dates and successful streak dates are local civil `YYYY-MM-DD` strings; they are never converted into UTC days.

After a historical restore, optional `data.state.restoredDay` retains the original day's `date`, `prayers`, `streak`, and `lastStreakDate`. This record survives restarts and later exports. It is a record of the **last historical restore**, not a daily activity log. A later historical restore replaces this record. It is not displayed as today's progress or used to award streaks.

## Validate, preview, commit

Import uses Android `ACTION_OPEN_DOCUMENT` for `application/json`. Kotlin reads streams in 8 KB chunks off the UI thread and stops above **1 MiB (1,048,576 bytes)**, including when a provider gives no size. Dart independently enforces the limit and strict UTF-8 parsing.

Validation checks the format, supported integer schema version, required fields and types, real calendar dates and timezone-qualified timestamps, supported prayer/Dhikr IDs, completion/count consistency, unique completion IDs, nonnegative integer counters and streaks, custom target 1–1000 and count ≤ target, valid settings enums, and vibration 0–100 in multiples of 5. Positive streaks require a last successful date, which cannot follow the progress date. A completed day must already contain its successful streak evaluation; import cannot manufacture one. Historical records receive the same validation. Future progress dates are refused at commit with a prompt to check the device clock.

Only a validated file opens the preview. It shows backup date, prayer progress date, every prayer's totals and completed Dhikr, streak and successful date, Custom Mode progress, and included settings. It warns: **“Restoring this backup will replace your current saved progress and settings.”** Cancel, Back, or outside dismissal does not commit data. Restore requires the explicit Restore button.

Commit waits for prior queued saves and temporarily blocks mutations. It constructs detached candidate models, applies existing daily rollover rules, and selects the active prayer using the current local clock. The existing single preference key `tasbih.native.snapshot.v1` remains unchanged. State and settings are serialized into **one write**; there is no series of progress/settings keys to partially restore. Visible models are replaced only after success. A reported write failure triggers an attempt to restore the previous serialized snapshot, including the preferences cache. If recovery also fails, the operation reports that recovery could not be verified and keeps live models unchanged. Complete hardware/storage failure cannot guarantee disk recovery; success is never reported for such a failure.

The Android preference snapshot is the practical atomic unit. Process interruption before/after its native commit yields the old/new complete snapshot. The app does not claim stronger guarantees against filesystem corruption or hardware failure.

## Daily progress, old backups, compatibility

Version 1 is the first supported external backup schema. Version 0, future versions, unrelated browser JSON/localStorage, malformed files, and incompatible prayer/Dhikr IDs are explicitly rejected. App version is informational; schema version controls compatibility. Existing private snapshot version 1 is retained and loads without migration or reset; the optional historical record is additive.

Same-day restore recovers that day's counters and streak evaluation exactly. A previous day's counts never become today's completed progress: normal daily reset creates empty prayer progress. A streak survives from yesterday only under the existing consecutive-day and successful-day conditions; a week-old backup's active streak resets to zero, while its original streak and dated progress remain in `restoredDay` and its last successful date remains intact. Custom counts, target, and settings survive rollover. Restore does not merge progress or count a completed day twice. The existing local-midnight elapsed-day/DST semantics are preserved (see prayer documentation).

## Reinstall recovery — required device acceptance scenario

1. Count in several prayers, complete Dhikr, earn a valid streak, and change Custom Mode target/count and settings.
2. Export to **Downloads** or another user-controlled provider and wait for the success message.
3. Verify that the JSON file is visible in the system Files app and contains the expected dated state.
4. Uninstall, reinstall the APK, then use Settings → Import Backup to select that file.
5. Inspect the preview and confirm Restore. Verify recovered settings/custom progress, same-day prayer progress, and streak metadata. For a later-day reinstall, verify dated history and the normal daily rollover behavior.
6. Restart the app and verify that restored state remains saved.
7. Also exercise picker cancellation, confirmation cancellation, malformed files, an oversized file, and provider access failures.

This scenario passed on a dedicated fresh Android API 37 emulator using the actual system Files UI: confirmation cancellation, full-state import, a real Custom Mode count, export to Downloads, uninstall, file survival, empty reinstall, import, cold restart, and equivalent full-state re-export. Evidence is in `docs/validation/upgrade/android-backup-acceptance.txt` and `device-roundtrip.json`. Physical OEM devices and optional providers such as Google Drive still need manual acceptance testing. Automated Flutter tests additionally simulate cancellation, provider failures, invalid input, storage rollback, and historical restores.

## Privacy

Backups are plaintext personal progress/settings. Store them somewhere you trust and delete unwanted copies yourself. A file saved outside the application remains after uninstall if the user/provider retains it. Drive is just an optional user-chosen document provider; the app has no account, cloud synchronization, automatic cloud backup, backend, or internet dependency. Provider completion means its stream closed successfully; subsequent cloud upload behavior belongs to that provider.

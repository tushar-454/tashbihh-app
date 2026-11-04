# Smart prayer notifications (Android)

Prayer Notifications is enabled by default, subject to Android permission. Its
device-local preference is independent of backed-up AppSettings, so restoring
data or resetting counters cannot override an explicit notification opt-out.
The first foreground initialization requests POST_NOTIFICATIONS once on Android
13+. Denial/dismissal is remembered. Settings displays the actual application
and channel permission and links to Android settings instead of repeatedly
opening permission dialogs. Resuming reconciles permission changes.

## Progress and prayer-date semantics

One goal means completing one configured dhikr target, not tapping three times.
Three completed targets satisfy a prayer; custom counter taps do not contribute.
The native policy counts configured targets reached in the existing saved count
map. Completing a prayer cancels only that prayer's pending reminders.

This app resets **all five prayer counters at local midnight**, including Isha.
This behavior is deliberately preserved. Its synchronized Isha counter is active
both after the evening Isha start and between midnight and saved Fajr. Therefore
the one Isha reminder pair for a calendar progress date uses that date's early
Isha end (saved Fajr), evaluates that date's current counter, and never treats
yesterday's evening completions as today's progress. The configured JSON
fallback instead uses its normal evening Isha end, including existing grace.
There is no additional evening Isha reminder pair in synchronized mode.

Fajr ends at Sunrise in API schedules. Other canonical boundaries, configured
gaps/grace, disabled counters and counter selection rules are unchanged. Dart
exports `PrayerSchedule.endOf` and the explicit early-Isha boundary rather than
assuming all ends equal the next prayer start.

The summary belongs to the date of the evening Isha **start**, and is due three
elapsed hours later. If that instant falls after midnight, it reports the source
date's persisted counts. A small archive retains only the latest eight dated
five-prayer count maps; it does not introduce a new history UI or change streaks.
After midnight the source date's Isha counter has reset, so the summary does not
suggest completing that source date's Isha. Before midnight an incomplete,
still-available Isha can receive an invitation. Expanded summaries include all
five counts and statuses.

## Persistence and closed-app delivery

AndroidProgressStore reads/writes the **same** legacy FlutterSharedPreferences
key, `flutter.tasbih.native.snapshot.v1`. It preserves the JSON snapshot and cloud
metadata format. Existing installations need no progress migration. There is no
second live-progress database. The SharedPreferences Dart cache is not used for
this key on Android; location/cache preferences keep their existing store.

Native writes, archive updates, alarm reconciliation and receiver delivery use
one lock and one serialized executor. Progress and its derived dated archive are
committed together. After a successful write the engine cancels/reschedules
eligible alarms; delivery independently rereads the latest committed snapshot.
It never embeds hours-old progress in prebuilt notification text. Scheduling
failures cannot turn a successful counter commit into a failed counter write.
Hardware/storage failure still has the existing SharedPreferences durability
limits; only committed progress can be reported after process death.

Restore/reset marks a replacement commit; account identity changes are detected
inside the existing snapshot commit. These clear dated notification history,
visible feature notifications, and pending previous-date summaries. Pending
future events are reconciled against the replacement data. Authentication and
Drive transfers remain the cloud coordinator's responsibility.

The Android receiver runs short local work without launching a Flutter engine.
At delivery it checks preference, OS permission, channel, timezone, event time,
goal and consumed-event ledger. It generates fresh messages, including actual
remaining minutes if an inexact alarm is late. Reminders arriving after their
window ends are dropped. Summaries delayed six hours or more are dropped.

Events use `date/prayer/offset` identities in PendingIntent URIs and notification
tags, avoiding integer hash collisions. Consumed events are committed before
posting and never scheduled again, even after decreases, restart or duplicate
broadcasts. A crash between that commit and NotificationManager posting can
lose a notification: Android provides no atomic disk-commit-plus-post operation.
This intentionally favors avoiding duplicates. Actual posts are capped at eleven
per local date, including summaries delayed across midnight.

## Horizon, time changes and offline operation

Dart exports seven calendar dates using the timezone package's civil date
constructors and the existing counter's schedule/cache policy. Valid saved civil
times may remain the existing offline fallback; these are not claimed to be
fresh API times for future dates. There is no background GPS or network fetch.
An optional pending previous-date summary can also be retained. There are at
most 88 event identities (176 alarms when exact/inexact pairs are used).

Midnight, prayer schedule changes, resume and foreground clock/timezone events
refresh the plan. Native BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET and exact
access grants rearm eligible future events from the persisted plan. Past due
events are not turned into immediate catch-up notifications. Timezone mismatch
cancels scheduling until Flutter exports a compatible plan; it never reinterprets
old absolute instants in a new zone. After seven days without opening the app,
scheduling stops until the next foreground reconciliation. No periodic jobs,
polling service, WorkManager or remote push dependency is used.

## Android permissions and reliability

- POST_NOTIFICATIONS: runtime permission on Android 13+.
- RECEIVE_BOOT_COMPLETED: restore still-valid alarms after unlock/reboot.
- SCHEDULE_EXACT_ALARM: optional user-controlled special access on Android 12+;
  Android 14 normally denies it initially. The app never requests USE_EXACT_ALARM.
- Existing VIBRATE permission supplies standard feedback. The default-importance
  prayer channel uses Android's normal sound/vibration and private lock-screen
  visibility; users retain control of channel sound and importance.

Without exact access the engine uses setAndAllowWhileIdle. With access it uses
setExactAndAllowWhileIdle and a paired inexact backup. Revoking exact access can
kill the process and remove exact alarms without a revocation broadcast; the
inexact backup survives and the delivery ledger prevents double posting. A
SecurityException during exact scheduling also falls back to inexact delivery.
Granting exact access is optional through Settings; it is never a startup gate.

Doze, battery restrictions, OEM policies and inexact-alarm batching can delay or
suppress delivery. Force-stopping the app blocks its alarms/receivers until the
user opens it again. Reboot cannot deliver before credential-encrypted storage
is available. No background solution can promise second-accurate delivery in
all these states. Notification permission or channel blocking always wins.

Taps open the existing app. A prayer is selected only if the ordinary controller
selection rules permit it; otherwise its normal current state is shown. Expired
counting is never enabled. Summary taps open home because there is no existing
daily history screen. Native intent consumption handles cold start and resume;
already-open taps notify Flutter once through the method channel.

## Files and dependency choices

- `lib/core/notifications/prayer_notifications.dart`: timezone-aware plan,
  Android progress store, settings/permission bridge.
- `PrayerNotificationPolicy.kt`: sole reminder/summary eligibility and messages.
- `PrayerNotifications.kt`: atomic storage/archive, alarms, receiver, channels,
  delivery ledger and fresh notification generation.
- `MainActivity.kt`: narrow platform channel, permission and tap bridge.
- `main.dart`, `app.dart`, `counter_screen.dart`, `settings_panel.dart`: wiring,
  lifecycle reconciliation and existing Settings integration.
- `progress_repository.dart`, `counter_controller.dart`: mark replacement data
  commits without changing counter/streak/cloud behavior.
- Android manifest/icon: permission declarations, non-exported system/alarm
  receiver, monochrome notification icon.
- `test/prayer_notifications_test.dart` and Android `src/test/...`: deterministic
  plan, storage, settings, policy and Robolectric lifecycle/delivery tests.
- `android/app/build.gradle.kts`: test-only dependencies and AGP 9 host-test asset
  dependency; release signing and workflows are unchanged.

No Flutter/runtime dependencies were added. Existing timezone 0.11.2 is reused,
as is the existing native timezone channel. Evaluated flutter_local_notifications
22.3.3 and flutter_timezone 5.1.1; neither is needed for this Android-native
delivery-time policy. Test dependencies are JUnit 4.13.2 and Robolectric 4.16.1.

Primary references: [Android alarms](https://developer.android.com/develop/background-work/services/alarms),
[notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission),
[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications),
[flutter_timezone](https://pub.dev/packages/flutter_timezone),
[Robolectric setup](https://robolectric.org/getting-started/).

## Physical-device acceptance

Use a development build or a separately installed validation build. A validation
key cannot update an installed app signed with your production key; preserve
progress with the existing backup flow before using an isolated test install.

1. Start the app on Android 13/14+, grant notifications, inspect Prayer
   Notifications in Settings. Deny once in a separate clean test installation
   and verify reopening does not prompt again. Change app/channel permission in
   Android settings and resume to verify the displayed status.
2. Compare the displayed prayer window with upcoming reminders. With fewer than
   three completed dhikr targets, leave the app open, background it, then swipe
   it from Recents in separate runs. Observe both offsets. Do not force-stop it.
3. Complete the third target before the first reminder, then between reminders
   in a separate run. Verify the corresponding future reminders are canceled
   and other prayers remain independent.
4. Observe Isha + three hours. Check all five expanded statuses. For a late Isha
   crossing midnight, verify the source date's archived progress and absence of
   an invitation to count in an expired source date.
5. Test with optional exact access denied, granted and revoked while backgrounded.
   Inexact delivery may be delayed; expired reminders should be dropped. Verify
   only one post per event even when exact and backup alarms both arrive.
6. Reboot before a future reminder, change device time/timezone, restore a backup,
   switch Drive accounts, reset data and disable/re-enable the toggle. Confirm no
   obsolete/duplicate summary or old account progress appears.
7. Repeat in battery saver/Doze and on an OEM phone. Test taps from a cold app,
   background app and visible app, including a tap after the prayer has expired.

Automated checks are recorded in `docs/validation/notifications/verification.md`.
Robolectric verifies Android-side behavior but does not substitute for physical
OS delivery/permission UI, OEM battery, or navigation acceptance testing.

# Android daily prayer times

The existing configuration, progress repository, counter controller, timer, and
Android local-clock event channel remain in use. No `AGENTS.md` was present in
the project or its ancestor directories during implementation.

## Data flow

1. Startup reads the last schedule from its own SharedPreferences key and reads
   the Android IANA timezone ID. Neither operation requests GPS or network access.
2. Counters initialize immediately with today's valid cache, otherwise the last
   compatible saved schedule, otherwise `assets/data/config.json`. Network/GPS initialization starts after the
   first screen frame and never blocks counting or Custom Mode.
3. When today's schedule is missing, an explanation precedes the first Android
   foreground permission request. Existing grants skip the explanation/request.
   Approximate location is accepted. There is no background location permission.
4. A single current-position request uses medium accuracy and a 20-second
   timeout. Coordinates are rounded to three decimal places before sending them
   to AlAdhan and saving them (approximately 110 metres of latitude).
5. `GET https://api.aladhan.com/v1/timings/DD-MM-YYYY` uses `method=1` (University
   of Islamic Sciences, Karachi) and `school=1` (Hanafi). Defaults are centralized
   in `PrayerCalculation`. The HTTP request has a 15-second timeout and closes
   its client on completion/failure.
6. Parsing validates HTTP/API status, Gregorian date, API timestamp date, all six
   times and their order, calculation metadata, coordinates, known IANA timezone,
   and agreement with the device's current date and UTC offset. An explicit
   device timezone ID is also saved to detect equal-offset timezone changes.
7. A successful response replaces one versioned preference value containing the
   prayer date, six times, coordinates, completion timestamp in UTC, method,
   school, API timezone, device timezone, and UTC offset. No location history is
   retained. Failed/malformed responses never reach storage. Reported storage
   failures attempt to restore the previous record and keep the active cache.
8. A change notification immediately refreshes selection, counter eligibility,
   hints, tooltips, and boundary timers. The progress preference is independent
   and is never replaced by schedule synchronization.

## Foreground synchronization

- The first screen and every foreground resume check today's cache before any
  permission, GPS, or API work. A valid cache causes no location/API request.
- The refresh date is the device's local calendar date. Local 00:00 triggers the
  next day's request while the app is open; UTC 00:00 is not a shared refresh
  instant. Local timezone rules already account for positive/negative offsets
  and daylight saving. When closed or suspended at midnight, the app checks and
  fetches the current day immediately on its next launch/resume.
- Existing counter timers schedule exact window boundaries and midnight. Their
  existing one-minute clock fallback only observes local time; it does not poll
  GPS or the API. A date/offset change triggers synchronization once.
- Android date, time, and timezone broadcasts also recheck the schedule. The
  native timezone query detects timezone-ID changes even at the same UTC offset.
- A shared in-flight future prevents overlapping requests. A midnight/timezone
  change during an operation discards outdated results and checks the new day
  after the guard is released. Successful dates are deduplicated by their cache.
- Transient network, GPS timeout, and storage failures get at most two timed
  retries, after 5 minutes and another 30 minutes. Later resumes and new dates
  can retry again. No permanent failed-date marker prevents recovery.
- Permission denial and disabled location services retry on resume or a new
  date, without recurring permission dialogs. A persistent prompt marker is
  committed before showing the first explanation. Android Settings can grant
  permission later; resume detects it automatically.
- Leaving the foreground cancels counter/retry timers and pending native GPS
  acquisition. Responses arriving while suspended are discarded. In-flight HTTP
  requests remain bounded by their timeout. There are no background jobs,
  scheduled services, location streams, location history, or manual sync buttons.

## Availability and fallback

| Counter | Synchronized availability |
| --- | --- |
| Fajr | Fajr inclusive → Sunrise exclusive |
| Dhuhr | Dhuhr inclusive → Asr exclusive |
| Asr | Asr inclusive → Maghrib exclusive |
| Maghrib | Maghrib inclusive → Isha exclusive |
| Isha | Isha → midnight; then midnight → saved Fajr |

After midnight, a refresh requests the new day's times. Until it succeeds,
the last compatible saved schedule continues to control every prayer window,
including Isha until its saved Fajr time. These older times are an offline
fallback and may differ from today's actual times; their original date is kept
so they never suppress the new day's refresh. Failed requests never replace the
saved record. With no compatible saved schedule, the entire JSON fallback
schedule applies; with the current JSON, Isha is closed after midnight.

JSON format and all JSON values are unchanged. Its existing end grace still
applies in fallback mode. Synchronized ends are canonical boundaries: grace
does not extend Fajr beyond Sunrise or overlap the next prayer. Custom Mode,
saved settings, counting data, backup behavior, streaks, and existing daily
progress rollover rules are preserved.

Today's valid cache works offline across restarts without location access and
without further API calls. An older saved record also works offline or with
location permission denied, while remaining due for refresh. Missing, corrupted,
future-dated, future-synchronized, wrong-calculation, or timezone-incompatible
records fall back to JSON. A small snackbar identifies the saved schedule's date
or configured fallback on failure; permission denials include the Android
Settings path. No failure prevents the app from functioning.

## Files and dependencies

New production files in `lib/core/prayer/`:
`prayer_times.dart`, `aladhan_client.dart`, `prayer_location.dart`,
`prayer_times_repository.dart`, and `prayer_time_sync.dart`.

Integration changes: `lib/main.dart`, `lib/core/time/prayer_schedule.dart`,
`lib/core/storage/progress_repository.dart`,
`lib/features/counter/counter_controller.dart`,
`lib/features/counter/counter_screen.dart`,
`lib/features/prayer/prayer_selector.dart`, the main Android manifest, and
`MainActivity.kt`. Configuration parsing and JSON assets are unchanged.

Direct dependencies added in `pubspec.yaml`/`pubspec.lock`:
`geolocator_android 5.2.1`, `http 1.6.0`, and `timezone 0.11.2`. The Android-only
location package avoids adding plugins/configuration for other platforms. Its
version is pinned because foreground cancellation uses its native one-shot
request cancellation bridge.

Tests: `prayer_times_test.dart`, `prayer_sync_test.dart`,
`prayer_counter_sync_test.dart`, `prayer_location_test.dart`,
`prayer_sync_support.dart`, and `fixtures/aladhan_timings.json` under `test/`.
The fixture was obtained from the public AlAdhan example endpoint for Dhaka on
3 November 2026; GPS, time, storage, permission channels, and HTTP are mocked in
automated tests. See [AlAdhan's API documentation](https://aladhan.com/prayer-times-api).

## Deliberate limits

- Synchronization runs only while the Android app is open or resumed.
- A device timezone set to an offset inconsistent with the geographic API
  timezone uses JSON fallback rather than displaying misleading local times.
- Missing or nonchronological times (including unusual polar-day responses)
  use JSON fallback. There is no separate high-latitude calculation UI.
- Location is checked once after successful daily caching. Travel within the
  same timezone/date is reflected at the next daily synchronization; timezone
  changes invalidate the old cache immediately when observed.
- SharedPreferences provides a single-value commit and best-effort recovery,
  not guaranteed durable transactional storage under device/storage failure.
- Native permission dialogs and hardware GPS still warrant a physical-device
  acceptance test; automated tests use mocked platform channels.

## Verification

- `flutter analyze`: passed with no issues.
- `flutter test --no-pub`: all 217 tests passed after the saved-schedule fallback
  update, covering local midnight in positive/negative UTC offsets, daily API
  deduplication, persisted restart behavior, permission denial, failed refreshes,
  cache replacement, and existing counting, streak, backup, and layout behavior.
- The following APK/manifest checks were performed for the initial daily-sync
  implementation; APK builds were not repeated for the saved-schedule update.
- `flutter build apk --debug`: passed during initial implementation.
- `flutter build apk --release`: passed during initial implementation; output is
  `build/app/outputs/flutter-apk/app-release.apk`.
- Inspected the merged release manifest and APK permissions: internet, coarse
  location, and fine location are present; background location is absent.
- Parsed the live AlAdhan Dhaka response and retained it as a deterministic test
  fixture. Actual Android permission dialogs/hardware GPS were not exercised.

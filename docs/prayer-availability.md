# Prayer availability

## Authoritative schedule and buffer policy

`assets/data/config.json` remains the schedule source of truth. Its canonical times match the original repository's [config.js](https://github.com/tushar-454/tasbihh/blob/main/config.js), checked against the actual file, and its window/streak behavior follows [script.js](https://github.com/tushar-454/tasbihh/blob/main/script.js). The repository README lists different example times; those examples are not used.

| Prayer | Inclusive local start | Exclusive canonical end | Default eligible duration |
|---|---|---|---|
| Fajr | 04:45 | 06:00 | 75 minutes |
| Dhuhr | 12:00 | 15:00 | 180 minutes |
| Asr | 16:45 | 18:00 | 75 minutes |
| Maghrib | 18:45 | 20:00 | 75 minutes |
| Isha | 20:30 | 22:00 | 90 minutes |

`prayerEndGraceMinutes` centralizes the configurable end buffer in the same configuration asset. **The shipped default is 0 minutes.** The original end boundaries and intentional inactive gaps remain intact: enlarging windows would change the source's counting restrictions. The existing 75–180 minute windows are retained. There is no early-start buffer. This limitation is deliberate, rather than assuming that time in a configured gap is available for counting.

To explicitly permit extending into gaps in a future configuration, set `prayerEndGraceMinutes` to an integer between 0 and 180. For example 15 allows Fajr until 06:15, Dhuhr until 15:15, Asr until 18:15, Maghrib until 20:15, and Isha until 22:15. Canonical starts remain unchanged. This is a build configuration, not a new user preference. No schedule editing UI is added.

## Shared algorithm

`PrayerSchedule` is shared by configuration lookup, controller eligibility, ended-window styling, and prayer status UI. It orders definitions by canonical start and caps each effective end at the earlier of canonical end + configured grace, the following canonical start, or local midnight for Isha. Starts are inclusive and ends exclusive, including subsecond boundary instants. It returns exactly one prayer ID or null. Latest canonical start wins deterministically if a future configuration contains overlapping windows. An earlier prayer cannot stay available after the next starts; nothing enables the next prayer early.

`nextTransition` returns the next configured start, effective end, or local midnight. The controller checks eligibility again **inside every increment**, using its injectable clock (`DateTime.now` by default), before touching counts/completions/streaks. A stale UI, keyboard activation, accessibility action, rapid taps, or full-screen background tap cannot bypass the rules. Reaching a target still caps counting. Custom Mode retains its independent count/target/reset behavior at any hour.

The existing selector behavior is preserved: during an active window only that prayer is selectable in Prayer Mode; during gaps all prayers can be selected for inspection but none can count. Custom Mode permits all selections. An active prayer is selected automatically on refresh and shown as “Available now”; gaps show “Not available at this time.” Inactive tiles and the counter's muted count/semantics make restrictions visible. Tooltips expose each prayer's current status.

## Clock, midnight, lifecycle

All comparisons use **device local civil date/hour/minute**, with no Bangladesh offset, location, astronomy, GPS, API, network, or fixed current date. Android broadcasts `TIME_SET`, `TIMEZONE_CHANGED`, and `DATE_CHANGED` refresh the controller while the activity is started. A single timer targets the next boundary with a maximum one-minute watchdog for missed events. It does not poll every second. Timers stop when the app leaves resumed state and restart with an immediate refresh on resume. Broadcast listeners and timers are disposed with their owners. No background service, alarm, or wake lock is added.

At midnight there is no active prayer. The existing daily rollover resets prayer counts/completions/selected Dhikr, preserving Custom Mode progress/settings and applying existing streak continuity rules. Restart, resume, clock/date jump, timezone change, and import all re-evaluate the schedule from local time. If the user moves the device date backwards, normal existing rollover semantics apply; importing a future-dated progress snapshot is refused to avoid accidental loss from an incorrect device clock.

The original streak semantics remain: all five prayers must each have at least three completed Dhikr, evaluation increments once per successful civil date, and last successful date is retained after a break. Consecutive-day calculation still floors elapsed milliseconds between local midnights, as in the existing Flutter code and JavaScript. A 23-hour DST spring-forward day therefore breaks continuity; this preexisting quirk is intentionally not changed in this update.

## Verification

Automated tests cover each start and end immediately before/at/after, every second of a full day with grace 0/15/60/180 (`eligibleCount <= 1`), gaps, configured grace, overlap resolution, midnight/date rollover, fake clock jumps, real local timezone conversion, stale rapid taps, Custom Mode independence, timer updates, injected clock-change broadcasts, and pause/resume across a transition. Existing streak/DST tests remain in the suite. A fresh Android API 37 emulator additionally passed actual local-clock changes to all five starts, blocked gap taps, live timezone changes (UTC / America/Los_Angeles), pause/resume across a clock change, foreground midnight rollover, and Custom Mode counting at midnight. See `docs/validation/upgrade/android-prayer-acceptance.txt`. Real Files export/import and uninstall/reinstall recovery also passed; optional cloud document providers and physical OEM devices remain for manual acceptance.

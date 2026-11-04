import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../config/tasbih_config.dart';
import '../models/app_state.dart';
import '../storage/progress_repository.dart';
import '../time/prayer_schedule.dart';

/// Dart exports the existing counter windows; Android alone owns reminder
/// eligibility, messages, alarms and delivery-time progress evaluation.
class NotificationPlan {
  static Map<String, Object> build({
    required DateTime now,
    required String zone,
    required TasbihConfig config,
    required PrayerSchedule Function(DateTime) scheduleFor,
  }) {
    tz_data.initializeTimeZones();
    final location = const {'UTC', 'GMT', 'Etc/UTC', 'Etc/GMT'}.contains(zone)
        ? tz.UTC
        : tz.getLocation(zone);
    final local = tz.TZDateTime.from(now, location);
    final days = <Map<String, Object>>[];
    // Seven days of the same valid saved/configured civil-time fallback used by
    // the counter. No future API times are invented and no background fetch runs.
    for (var offset = 0; offset < 7; offset++) {
      final day = tz.TZDateTime(
        location,
        local.year,
        local.month,
        local.day + offset,
      );
      final schedule = scheduleFor(offset == 0 ? local : day);
      int instant(int minute) => tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      ).millisecondsSinceEpoch;
      days.add({
        'date': dateKey(day),
        'dayStart': instant(0),
        'dayEnd': instant(1440),
        'windows': [
          for (final prayer in schedule.prayers)
            {
              'id': prayer.id,
              'start': instant(
                prayer.id == 'isha' && schedule.earlyIshaEnd != null
                    ? 0
                    : prayer.start,
              ),
              // Progress belongs to a calendar date, even during early Isha.
              // Its evening segment must not create a second pair of reminders.
              'end': instant(
                prayer.id == 'isha' && schedule.earlyIshaEnd != null
                    ? schedule.earlyIshaEnd!
                    : schedule.endOf(prayer),
              ),
            },
        ],
        'ishaStart': instant(
          schedule.prayers.firstWhere((p) => p.id == 'isha').start,
        ),
        'ishaEnd': instant(
          schedule.earlyIshaEnd == null
              ? schedule.endOf(
                  schedule.prayers.firstWhere((p) => p.id == 'isha'),
                )
              : 1440,
        ),
      });
    }
    return {
      'version': 1,
      'zone': zone,
      'days': days,
      'targets': {
        for (final prayer in config.prayers)
          prayer.id: {
            for (final d in config.forPrayer(prayer.id)) d.id: d.target,
          },
      },
    };
  }
}

/// Uses the existing Android preference key. Writing progress and reconciling
/// alarms share a native lock with the delivery receiver (no stale mirror).
class AndroidProgressStore implements ReplacementSnapshotStore {
  static const channel = MethodChannel('tasbih/prayer_notifications');
  @override
  Future<String?> read() => channel.invokeMethod<String>('readProgress');
  @override
  Future<void> write(String value) => _write(value, false);
  @override
  Future<void> writeReplacement(String value) => _write(value, true);
  Future<void> _write(String value, bool replacement) =>
      channel.invokeMethod<void>('writeProgress', {
        'value': value,
        'replacement': replacement,
      });
}

class PrayerNotifications extends ChangeNotifier {
  PrayerNotifications({MethodChannel? channel})
    : channel = channel ?? AndroidProgressStore.channel {
    this.channel.setMethodCallHandler((call) async {
      if (call.method == 'tapAvailable') onTapAvailable?.call();
    });
  }
  final MethodChannel channel;
  VoidCallback? onTapAvailable;
  bool enabled = true, allowed = false, exact = false, busy = false;
  String? error;
  String? _lastPlan;
  bool _disposed = false;
  String get status =>
      error ??
      (!enabled
          ? 'Off'
          : !allowed
          ? 'Blocked in Android notification settings'
          : exact
          ? 'On · precise alarms allowed'
          : 'On · Android may delay reminders');

  Future<void> refresh({bool requestPermission = false}) async {
    await _run(() async {
      final state = await channel.invokeMapMethod<String, dynamic>(
        requestPermission ? 'requestPermission' : 'status',
      );
      enabled = state?['enabled'] == true;
      allowed = state?['allowed'] == true;
      exact = state?['exact'] == true;
    });
  }

  Future<void> configure(Map<String, Object> plan) async {
    final encoded = jsonEncode(plan);
    if (encoded == _lastPlan) return;
    await _run(() async {
      await channel.invokeMethod<void>('configure', encoded);
      _lastPlan = encoded;
    });
  }

  Future<void> setEnabled(bool value) async {
    if (busy) return;
    await _run(() async {
      await channel.invokeMethod<void>('setEnabled', value);
      enabled = value;
    });
    await refresh(requestPermission: value);
  }

  Future<void> openSettings({bool alarms = false}) => _run(() async {
    await channel.invokeMethod<void>(alarms ? 'alarmSettings' : 'settings');
  });

  Future<String?> takeTap() async {
    try {
      return await channel.invokeMethod<String>('takeTap');
    } on PlatformException {
      return null;
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_disposed) return;
    busy = true;
    try {
      await operation();
      error = null;
    } catch (_) {
      error = 'Notification settings unavailable. Please retry.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}

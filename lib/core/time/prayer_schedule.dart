import 'dart:math' as math;

import '../config/tasbih_config.dart';
import '../localization/app_localizations.dart';

/// Fixed local civil-time windows. Starts inclusive; ends exclusive.
/// A nonzero end grace explicitly opts into extending configured inactive gaps.
/// Grace never crosses midnight or the following prayer's canonical start.
class PrayerSchedule {
  PrayerSchedule(
    List<PrayerDefinition> definitions, {
    this.endGraceMinutes = 0,
    this.earlyIshaEnd,
  }) : prayers = [...definitions]..sort((a, b) => a.start.compareTo(b.start)) {
    if (endGraceMinutes < 0 || endGraceMinutes > 180) {
      throw ArgumentError.value(endGraceMinutes, 'endGraceMinutes');
    }
  }
  final List<PrayerDefinition> prayers;
  final int endGraceMinutes;

  /// Set for API schedules. Early Isha ends at the saved Fajr time, using the
  /// last available schedule until the current day's synchronization succeeds.
  final int? earlyIshaEnd;

  String windowLabel(String id) => windowMessage(id).english;
  AppMessage windowMessage(String id) {
    final prayer = prayers.firstWhere((p) => p.id == id);
    final times = prayer.windowLabel.split(' – ');
    return id == 'isha' && earlyIshaEnd != null
        ? AppMessage('isha_window', {'start': times.first})
        : AppMessage('prayer_window', {
            'start': times.first,
            'end': times.last,
          });
  }

  int endOf(PrayerDefinition prayer) {
    final index = prayers.indexOf(prayer);
    final nextStart = index + 1 < prayers.length
        ? prayers[index + 1].start
        : 1440;
    return math.min(prayer.end + endGraceMinutes, nextStart);
  }

  String? activePrayer(DateTime local) {
    final minute = local.hour * 60 + local.minute;
    if (earlyIshaEnd != null && minute < earlyIshaEnd!) return 'isha';
    // Latest canonical start wins even if malformed configuration overlaps.
    for (final prayer in prayers.reversed) {
      if (minute >= prayer.start && minute < endOf(prayer)) return prayer.id;
    }
    return null;
  }

  bool eligible(String prayer, DateTime local) => activePrayer(local) == prayer;
  bool ended(String id, DateTime local) => id == 'isha' && earlyIshaEnd != null
      ? local.hour * 60 + local.minute >= earlyIshaEnd! &&
            local.hour * 60 + local.minute <
                prayers.firstWhere((p) => p.id == id).start
      : local.hour * 60 + local.minute >=
            endOf(prayers.firstWhere((p) => p.id == id));

  DateTime nextTransition(DateTime local) {
    final candidates = <DateTime>[
      DateTime(local.year, local.month, local.day + 1),
      for (final p in prayers) ...[
        DateTime(
          local.year,
          local.month,
          local.day,
          p.start ~/ 60,
          p.start % 60,
        ),
        DateTime(
          local.year,
          local.month,
          local.day,
          endOf(p) ~/ 60,
          endOf(p) % 60,
        ),
      ],
    ].where((d) => d.isAfter(local)).toList()..sort();
    return candidates.first;
  }
}

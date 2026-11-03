import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../config/tasbih_config.dart';
import '../models/app_state.dart';
import '../time/prayer_schedule.dart';

/// One place to change calculation defaults when customization is introduced.
class PrayerCalculation {
  const PrayerCalculation({this.method = 1, this.school = 1});
  final int method;
  final int school;
  String get schoolName => school == 1 ? 'HANAFI' : 'STANDARD';
}

class PrayerCoordinates {
  PrayerCoordinates(double latitude, double longitude)
    : latitude = (latitude * 1000).roundToDouble() / 1000,
      longitude = (longitude * 1000).roundToDouble() / 1000 {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Invalid location');
    }
  }
  // About 110 metres: retain only the coordinates needed for calculation.
  final double latitude, longitude;
}

/// Validated, immutable daily civil times in the API's IANA timezone.
class PrayerTimes {
  PrayerTimes._({
    required this.date,
    required this.times,
    required this.coordinates,
    required this.syncedAt,
    required this.calculation,
    required this.timezone,
    required this.deviceTimezone,
    required this.utcOffsetMinutes,
  });

  static const names = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  static bool _zonesLoaded = false;
  final String date, timezone, deviceTimezone;
  final Map<String, int> times;
  final PrayerCoordinates coordinates;
  final DateTime syncedAt;
  final PrayerCalculation calculation;
  final int utcOffsetMinutes;

  static tz.Location _zone(String name) {
    if (!_zonesLoaded) {
      tz_data.initializeTimeZones();
      _zonesLoaded = true;
    }
    try {
      return tz.getLocation(name);
    } catch (_) {
      throw const FormatException('Unknown prayer timezone');
    }
  }

  static String apiDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';

  static int _minute(dynamic raw) {
    if (raw is! String) throw const FormatException('Missing prayer time');
    final match = RegExp(r'^(\d{2}):(\d{2})(?:\s+\([^()\r\n]+\))?$')
        .firstMatch(raw.trim());
    if (match == null) throw const FormatException('Invalid prayer time');
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) {
      throw const FormatException('Invalid prayer time');
    }
    return hour * 60 + minute;
  }

  factory PrayerTimes.fromApi(
    Map<String, dynamic> json, {
    required DateTime requestedAt,
    required PrayerCoordinates coordinates,
    required String deviceTimezone,
    PrayerCalculation calculation = const PrayerCalculation(),
  }) {
    if (json['code'] != 200 || json['status'] != 'OK') {
      throw const FormatException('Prayer API returned an error');
    }
    final data = json['data'] as Map<String, dynamic>;
    if (data['date']['gregorian']['date'] != apiDate(requestedAt)) {
      throw const FormatException('Prayer API returned a different date');
    }
    final meta = data['meta'] as Map<String, dynamic>;
    final timestamp = int.tryParse('${data['date']['timestamp']}');
    if (timestamp == null ||
        dateKey(
              tz.TZDateTime.from(
                DateTime.fromMillisecondsSinceEpoch(
                  timestamp * 1000,
                  isUtc: true,
                ),
                _zone(meta['timezone'] as String),
              ),
            ) !=
            dateKey(requestedAt)) {
      throw const FormatException('Invalid prayer API timestamp');
    }
    if (meta['method']['id'] != calculation.method ||
        meta['school'] != calculation.schoolName) {
      throw const FormatException('Unexpected calculation settings');
    }
    final lat = meta['latitude'] as num;
    final lon = meta['longitude'] as num;
    if (!lat.isFinite ||
        !lon.isFinite ||
        (lat - coordinates.latitude).abs() > .01 ||
        (lon - coordinates.longitude).abs() > .01) {
      throw const FormatException('Prayer API returned a different location');
    }
    final result = PrayerTimes._(
      date: dateKey(requestedAt),
      times: Map.unmodifiable({
        for (final name in names) name: _minute(data['timings'][name]),
      }),
      coordinates: coordinates,
      syncedAt: requestedAt.toUtc(),
      calculation: calculation,
      timezone: meta['timezone'] as String,
      deviceTimezone: deviceTimezone,
      utcOffsetMinutes: requestedAt.timeZoneOffset.inMinutes,
    );
    result._validate();
    if (!result.validFor(requestedAt, deviceTimezone, calculation)) {
      throw const FormatException('Prayer and device timezones do not agree');
    }
    return result;
  }

  void _validate() {
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null ||
        dateKey(parsedDate) != date ||
        dateKey(tz.TZDateTime.from(syncedAt, _zone(timezone))) != date ||
        dateKey(tz.TZDateTime.from(syncedAt, _zone(deviceTimezone))) != date ||
        tz.TZDateTime.from(
              syncedAt,
              _zone(timezone),
            ).timeZoneOffset.inMinutes !=
            utcOffsetMinutes ||
        tz.TZDateTime.from(
              syncedAt,
              _zone(deviceTimezone),
            ).timeZoneOffset.inMinutes !=
            utcOffsetMinutes ||
        calculation.method < 0 ||
        calculation.school < 0 ||
        calculation.school > 1) {
      throw const FormatException('Invalid prayer date or timezone');
    }
    var previous = -1;
    for (final name in names) {
      final minute = times[name];
      if (minute == null || minute <= previous || minute >= 1440) {
        throw const FormatException('Incomplete or unordered prayer times');
      }
      previous = minute;
    }
  }

  bool validFor(DateTime local, String deviceZone, PrayerCalculation settings) {
    final zoned = tz.TZDateTime.from(local, _zone(timezone));
    return date == dateKey(local) &&
        date == dateKey(zoned) &&
        deviceTimezone == deviceZone &&
        utcOffsetMinutes == local.timeZoneOffset.inMinutes &&
        zoned.timeZoneOffset == local.timeZoneOffset &&
        calculation.method == settings.method &&
        calculation.school == settings.school &&
        !syncedAt.isAfter(local.add(const Duration(minutes: 5)));
  }

  PrayerTimes synchronizedAt(DateTime now) => PrayerTimes.fromJson({
    ...toJson(),
    'syncedAt': now.toUtc().toIso8601String(),
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'times': times,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'syncedAt': syncedAt.toIso8601String(),
    'method': calculation.method,
    'school': calculation.school,
    'timezone': timezone,
    'deviceTimezone': deviceTimezone,
    'utcOffsetMinutes': utcOffsetMinutes,
  };

  factory PrayerTimes.fromJson(Map<String, dynamic> json) {
    final result = PrayerTimes._(
      date: json['date'] as String,
      times: Map.unmodifiable(Map<String, int>.from(json['times'] as Map)),
      coordinates: PrayerCoordinates(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      syncedAt: DateTime.parse(json['syncedAt'] as String).toUtc(),
      calculation: PrayerCalculation(
        method: json['method'] as int,
        school: json['school'] as int,
      ),
      timezone: json['timezone'] as String,
      deviceTimezone: json['deviceTimezone'] as String,
      utcOffsetMinutes: json['utcOffsetMinutes'] as int,
    );
    result._validate();
    return result;
  }

  PrayerSchedule schedule(TasbihConfig config) {
    const starts = {
      'fajr': 'Fajr',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
    };
    const ends = {
      'fajr': 'Sunrise',
      'dhuhr': 'Asr',
      'asr': 'Maghrib',
      'maghrib': 'Isha',
    };
    return PrayerSchedule([
      for (final prayer in config.prayers)
        PrayerDefinition(
          id: prayer.id,
          label: prayer.label,
          arabic: prayer.arabic,
          icon: prayer.icon,
          start: times[starts[prayer.id]]!,
          end: prayer.id == 'isha' ? 1440 : times[ends[prayer.id]]!,
        ),
    ], earlyIshaEnd: times['Fajr']);
    // Synchronized ends are canonical boundaries (especially Sunrise).
    // Configured grace remains in effect for the JSON fallback schedule.
  }
}

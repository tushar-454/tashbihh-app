import 'dart:convert';

import 'package:flutter/services.dart';

class PrayerDefinition {
  const PrayerDefinition({
    required this.id,
    required this.label,
    required this.arabic,
    required this.icon,
    required this.start,
    required this.end,
  });
  final String id, label, arabic, icon;
  final int start, end;
  bool isOpen(DateTime date) {
    final minutes = date.hour * 60 + date.minute;
    return minutes >= start && minutes < end;
  }

  bool isLocked(DateTime date) => date.hour * 60 + date.minute >= end;
  String get windowLabel => '${_time(start)} – ${_time(end)}';
  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

class Dhikr {
  const Dhikr({
    required this.id,
    required this.arabic,
    required this.transliteration,
    required this.meaning,
    required this.target,
    required this.prayers,
  });
  final String id, arabic, transliteration, meaning;
  final int target;
  final List<String> prayers;
}

class TasbihConfig {
  TasbihConfig({
    required this.prayers,
    required this.duas,
    required this.minimumStreakDuas,
  });
  final List<PrayerDefinition> prayers;
  final List<Dhikr> duas;
  final int minimumStreakDuas;
  factory TasbihConfig.fromJson(Map<String, dynamic> json) {
    int minutes(String value) {
      final parts = value.split(':').map(int.parse).toList();
      return parts[0] * 60 + parts[1];
    }

    return TasbihConfig(
      prayers: (json['prayers'] as List)
          .map(
            (p) => PrayerDefinition(
              id: p['id'],
              label: p['label'],
              arabic: p['arabic'],
              icon: p['icon'],
              start: minutes(json['${p['id']}TimeStart']),
              end: minutes(json['${p['id']}TimeEnd']),
            ),
          )
          .toList(),
      duas: (json['duas'] as List)
          .map(
            (d) => Dhikr(
              id: d['id'],
              arabic: d['arabic'],
              transliteration: d['transliteration'],
              meaning: d['meaning'],
              target: d['target'],
              prayers: List<String>.from(d['prayer']),
            ),
          )
          .toList(),
      minimumStreakDuas: json['MIN_COMPLETED_DUAS_PER_PRAYER_FOR_STREAK'],
    );
  }
  static Future<TasbihConfig> load() async => TasbihConfig.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/config.json'))
        as Map<String, dynamic>,
  );
  List<Dhikr> forPrayer(String id) =>
      duas.where((d) => d.prayers.contains(id)).toList();
  String? activePrayer(DateTime date) {
    for (final prayer in prayers) {
      if (prayer.isOpen(date)) return prayer.id;
    }
    return null;
  }

  PrayerDefinition prayer(String id) => prayers.firstWhere((p) => p.id == id);
}

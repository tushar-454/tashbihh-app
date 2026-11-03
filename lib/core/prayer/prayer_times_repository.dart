import 'dart:convert';

import '../storage/progress_repository.dart';
import 'prayer_times.dart';

class PrayerTimesRepository {
  PrayerTimesRepository(this.store);
  static const cacheKey = 'tasbih.prayer.schedule.v1';
  static const permissionKey = 'tasbih.prayer.location.prompt.v1';
  final SnapshotStore store;

  Future<PrayerTimes?> load() async {
    try {
      final raw = await store.read();
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1) return null;
      return PrayerTimes.fromJson(json['schedule'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PrayerTimes schedule) async {
    final snapshot = jsonEncode({'version': 1, 'schedule': schedule.toJson()});
    final previous = await store.read();
    try {
      // One preference value is the commit unit, independent of user progress.
      await store.write(snapshot);
    } catch (_) {
      if (previous != null) {
        try {
          await store.write(previous);
        } catch (_) {
          /* Keep active cache. */
        }
      }
      rethrow;
    }
  }
}

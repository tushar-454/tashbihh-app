import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/config/tasbih_config.dart';
import 'package:tashbihh/core/time/prayer_schedule.dart';

import 'test_support.dart';

void main() {
  final config = testConfig();
  test('all civil seconds have at most one eligible prayer, including opt-in grace', () {
    for (final grace in [0, 15, 60, 180]) {
      final schedule = PrayerSchedule(config.prayers, endGraceMinutes: grace);
      for (var second = 0; second < 86400; second++) {
        final now = DateTime(2026, 11, 2, 0, 0, second);
        expect(
          config.prayers.where((p) => schedule.eligible(p.id, now)).length,
          lessThanOrEqualTo(1),
        );
      }
    }
  });
  test('canonical boundaries, next transitions, gaps and date rollover', () {
    final s = config.schedule;
    expect(s.activePrayer(DateTime(2026, 11, 2, 4, 44, 59)), isNull);
    for (final p in config.prayers) {
      final start = DateTime(2026, 11, 2, 0, p.start);
      final end = DateTime(2026, 11, 2, 0, p.end);
      expect(s.activePrayer(start), p.id);
      expect(s.activePrayer(start.add(const Duration(minutes: 10))), p.id);
      expect(
        s.activePrayer(start.subtract(const Duration(microseconds: 1))),
        isNull,
      );
      expect(
        s.activePrayer(end.subtract(const Duration(microseconds: 1))),
        p.id,
      );
      expect(s.activePrayer(end), isNull);
      expect(s.activePrayer(end.add(const Duration(microseconds: 1))), isNull);
      expect(s.nextTransition(start), end);
    }
    expect(s.nextTransition(DateTime(2026, 11, 2, 23)), DateTime(2026, 11, 3));
    expect(s.activePrayer(DateTime(2026, 11, 3)), isNull);
    expect(s.activePrayer(DateTime(2026, 11, 3, 4, 45)), 'fajr');
  });
  test('15-minute grace explicitly extends ends, never starts', () {
    final s = PrayerSchedule(config.prayers, endGraceMinutes: 15);
    expect(s.activePrayer(DateTime(2026, 11, 2, 6, 14, 59)), 'fajr');
    expect(s.activePrayer(DateTime(2026, 11, 2, 6, 15)), isNull);
    expect(s.activePrayer(DateTime(2026, 11, 2, 11, 59)), isNull);
    final wide = PrayerSchedule(config.prayers, endGraceMinutes: 180);
    expect(wide.activePrayer(DateTime(2026, 11, 2, 18, 44, 59)), 'asr');
    expect(wide.activePrayer(DateTime(2026, 11, 2, 18, 45)), 'maghrib');
    expect(wide.activePrayer(DateTime(2026, 11, 3)), isNull);
  });
  test('overlaps resolve to the latest canonical start deterministically', () {
    final s = PrayerSchedule([
      const PrayerDefinition(
        id: 'a',
        label: '',
        arabic: '',
        icon: '',
        start: 100,
        end: 400,
      ),
      const PrayerDefinition(
        id: 'b',
        label: '',
        arabic: '',
        icon: '',
        start: 200,
        end: 500,
      ),
    ]);
    expect(s.activePrayer(DateTime(2026, 11, 2, 0, 199)), 'a');
    expect(s.activePrayer(DateTime(2026, 11, 2, 0, 200)), 'b');
    expect(s.eligible('a', DateTime(2026, 11, 2, 0, 200)), isFalse);
  });
  test('rapid stale taps, clock jumps, local timezone representation and Custom Mode', () {
    final h = Harness();
    addTearDown(h.controller.dispose);
    expect(h.controller.increment(), isTrue);
    h.now = DateTime(2026, 11, 2, 12); // device clock/timezone wall-clock jump
    for (var i = 0; i < 50; i++) {
      expect(h.controller.increment(), isFalse);
    }
    h.controller.refresh();
    expect(h.controller.activePrayer, 'dhuhr');
    expect(h.controller.increment(), isTrue);
    h.now = DateTime(2026, 11, 3, 0);
    expect(h.controller.increment(), isFalse);
    expect(h.controller.state.date, '2026-11-03');
    h.controller.toggleMode();
    expect(h.controller.increment(), isTrue);
    // Schedule uses the supplied local civil fields, never a fixed UTC offset.
    expect(
      config.schedule.activePrayer(
        DateTime.parse('2026-11-02T12:00:00+06:00').toLocal(),
      ),
      config.schedule.activePrayer(
        DateTime.parse('2026-11-02T06:00:00Z').toLocal(),
      ),
    );
  });
}

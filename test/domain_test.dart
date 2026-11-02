import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';
import 'package:tashbihh/features/streak/streak_rules.dart';

import 'test_support.dart';

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.controller.dispose());
  test('complete authoritative dataset and prayer eligibility', () {
    expect(h.config.duas.length, 11);
    expect(h.config.forPrayer('fajr').length, 11);
    expect(h.config.forPrayer('dhuhr').length, 7);
    expect(h.config.forPrayer('asr').length, 7);
    expect(h.config.forPrayer('maghrib').length, 9);
    expect(h.config.forPrayer('isha').length, 10);
    expect(h.config.duas.map((d) => d.target), [
      33,
      33,
      34,
      100,
      33,
      33,
      1,
      3,
      10,
      100,
      10,
    ]);
    expect(h.config.duas.first.arabic, 'سُبْحَانَ اللَّهِ');
  });
  for (final prayer in testConfig().prayers) {
    test('${prayer.label} exact start inclusive and end exclusive', () {
      final start = DateTime(
        2026,
        11,
        2,
        prayer.start ~/ 60,
        prayer.start % 60,
      );
      final end = DateTime(2026, 11, 2, prayer.end ~/ 60, prayer.end % 60);
      expect(
        h.config.activePrayer(start.subtract(const Duration(milliseconds: 1))),
        isNull,
      );
      expect(h.config.activePrayer(start), prayer.id);
      expect(
        h.config.activePrayer(end.subtract(const Duration(milliseconds: 1))),
        prayer.id,
      );
      expect(h.config.activePrayer(end), isNull);
      expect(prayer.isLocked(end), isTrue);
    });
  }
  test('inactive selected prayer is blocked and cannot be selected during a window', () {
    h.controller.state.selectedPrayer = 'dhuhr';
    expect(h.controller.increment(), isFalse);
    expect(h.controller.count, 0);
    expect(h.controller.canSelect('dhuhr'), isFalse);
    h.controller.selectPrayer('asr');
    expect(h.controller.state.selectedPrayer, 'dhuhr');
    h.controller.refresh();
    expect(h.controller.state.selectedPrayer, 'fajr');
  });
  test('gap allows reviewing prayers but blocks counting', () {
    h.now = DateTime(2026, 11, 2, 11);
    h.controller.refresh();
    h.controller.selectPrayer('isha');
    expect(h.controller.state.selectedPrayer, 'isha');
    expect(h.controller.increment(), isFalse);
  });
  test('window ending is enforced on tap without a heartbeat', () {
    expect(h.controller.increment(), isTrue);
    h.now = DateTime(2026, 11, 2, 6);
    expect(h.controller.increment(), isFalse);
    expect(h.controller.count, 1);
  });
  test('Dua target caps counts and adds completion once', () {
    h.controller.selectDua('ayatulkursi');
    expect(h.controller.increment(), isTrue);
    expect(h.controller.count, 1);
    expect(h.controller.completed(h.controller.dua), isTrue);
    expect(h.controller.increment(), isFalse);
    h.controller.resetCounter();
    expect(h.controller.count, 1);
    expect(h.controller.progress.completed, {'ayatulkursi'});
  });
  test('independent per-Dua progress and disallowed selection', () {
    h.controller.increment();
    h.controller.selectDua('alhamdulillah');
    expect(h.controller.count, 0);
    h.controller.increment();
    h.controller.increment();
    h.controller.selectDua('subhanallah');
    expect(h.controller.count, 1);
    h.now = DateTime(2026, 11, 2, 12);
    h.controller.refresh();
    h.controller.selectDua('lahawla');
    expect(h.controller.dua.id, 'subhanallah');
    expect(h.controller.count, 0);
  });
  test(
    'incomplete prayer reset remains available outside window, like source',
    () {
      h.controller.increment();
      h.now = DateTime(2026, 11, 2, 7);
      h.controller.resetCounter();
      expect(h.controller.count, 0);
    },
  );
  test('Custom Mode is independent, unlimited by time, target capped and resettable', () {
    h.controller.increment();
    h.controller.toggleMode();
    h.now = DateTime(2026, 11, 2, 11);
    h.controller.setCustomTarget(10);
    for (var i = 0; i < 15; i++) {
      h.controller.increment();
    }
    expect(h.controller.count, 10);
    expect(h.controller.done, isTrue);
    h.controller.resetCounter();
    expect(h.controller.count, 0);
    h.controller.toggleMode();
    expect(h.controller.count, 1);
    h.controller.toggleMode();
    expect(h.controller.count, 0);
    h.controller.setCustomTarget(1001);
    expect(h.controller.target, 1000);
    h.controller.setCustomTarget(0);
    expect(h.controller.target, 10);
  });
  test(
    'reducing custom target clamps count and preserves through daily rollover',
    () {
      h.controller.toggleMode();
      for (var i = 0; i < 35; i++) {
        h.controller.increment();
      }
      h.controller.setCustomTarget(20);
      expect(h.controller.count, 20);
      h.now = DateTime(2026, 11, 3);
      h.controller.refresh();
      expect(h.controller.count, 20);
      expect(h.controller.target, 20);
      expect(h.controller.settings.mode, AppMode.custom);
    },
  );
  test('midnight clears all prayer data, preserves settings, custom and last success', () {
    h.controller.increment();
    h.controller.selectDua('ayatulkursi');
    h.controller.increment();
    h.controller.toggleStyle();
    h.controller.setIntensity(75);
    h.controller.state.customCount = 25;
    h.controller.state.customTarget = 200;
    h.controller.state.streak = 4;
    h.controller.state.lastStreakDate = '2026-11-02';
    h.now = DateTime(2026, 11, 3);
    h.controller.refresh();
    expect(
      h.controller.state.prayers.values.every(
        (p) =>
            p.counts.isEmpty &&
            p.completed.isEmpty &&
            p.selectedDuaId == 'subhanallah',
      ),
      isTrue,
    );
    expect(h.controller.state.streak, 4);
    expect(h.controller.state.lastStreakDate, '2026-11-02');
    expect(h.controller.state.customCount, 25);
    expect(h.controller.state.customTarget, 200);
    expect(h.controller.settings.style, CounterStyle.modern);
    expect(h.controller.settings.vibrationIntensity, 75);
  });
  test('streak success requires three completed Duas in each prayer', () {
    h.completeDay();
    expect(h.controller.state.streak, 1);
    expect(h.controller.state.lastStreakDate, '2026-11-02');
    expect(
      h.controller.state.prayers.values.every((p) => p.completed.length == 3),
      isTrue,
    );
  });
  test('missing one prayer or only two Isha Duas cannot earn streak', () {
    for (final p in h.config.prayers.take(4)) {
      h.controller.state.prayers[p.id]!.completed.addAll([
        'subhanallah',
        'alhamdulillah',
        'allahuakbar',
      ]);
    }
    h.now = DateTime(2026, 11, 2, 23);
    expect(StreakRules.evaluate(h.controller.state, h.config, h.now), isFalse);
    h.controller.state.prayers['isha']!.completed.addAll([
      'subhanallah',
      'alhamdulillah',
    ]);
    expect(StreakRules.evaluate(h.controller.state, h.config, h.now), isFalse);
  });
  test('streak check mirrors source: no independent Isha time gate', () {
    for (final p in h.config.prayers) {
      h.controller.state.prayers[p.id]!.completed.addAll([
        'subhanallah',
        'alhamdulillah',
        'allahuakbar',
      ]);
    }
    expect(
      StreakRules.evaluate(
        h.controller.state,
        h.config,
        DateTime(2026, 11, 2, 4),
      ),
      isTrue,
    );
  });
  test('duplicate streak prevention on heartbeat and extra counts', () {
    h.completeDay();
    for (var i = 0; i < 5; i++) {
      h.controller.refresh();
    }
    h.controller.selectDua('ayatulkursi');
    h.controller.increment();
    expect(h.controller.state.streak, 1);
  });
  test('consecutive successful days increment streak', () {
    h.completeDay();
    h.now = DateTime(2026, 11, 3);
    h.controller.refresh();
    h.completeDay();
    expect(h.controller.state.streak, 2);
    expect(h.controller.state.lastStreakDate, '2026-11-03');
  });
  test('skipped day breaks streak; next success starts at one', () {
    h.completeDay();
    h.now = DateTime(2026, 11, 4);
    h.controller.refresh();
    expect(h.controller.state.streak, 0);
    expect(h.controller.state.lastStreakDate, '2026-11-02');
    h.completeDay();
    expect(h.controller.state.streak, 1);
  });
  test('unfinished day breaks streak at next midnight', () {
    h.completeDay();
    h.now = DateTime(2026, 11, 3);
    h.controller.refresh();
    expect(h.controller.state.streak, 1);
    h.now = DateTime(2026, 11, 4);
    h.controller.refresh();
    expect(h.controller.state.streak, 0);
  });
  test('local midnight arithmetic handles year/month/leap-day boundaries', () {
    expect(localDayDifference('2026-12-31', '2027-01-01'), 1);
    expect(localDayDifference('2028-02-28', '2028-03-01'), 2);
  });
  test(
    'source DST arithmetic preserves 23-hour, 25-hour and negative quirks',
    () {
      final springFrom = DateTime.parse('2026-03-08T00:00:00-05:00');
      final springTo = DateTime.parse('2026-03-09T00:00:00-04:00');
      expect(elapsedLocalDays(springFrom, springTo), 0);
      final autumnFrom = DateTime.parse('2026-11-01T00:00:00-04:00');
      final autumnTo = DateTime.parse('2026-11-02T00:00:00-05:00');
      expect(elapsedLocalDays(autumnFrom, autumnTo), 1);
      expect(elapsedLocalDays(autumnTo, autumnFrom), -2);
    },
  );
  test('settings and both counting modes persist across a restart', () async {
    h.controller.increment();
    h.controller.toggleMode();
    h.controller.setCustomTarget(220);
    h.controller.increment();
    h.controller.toggleStyle();
    h.controller.setIntensity(65);
    await h.controller.flush();
    final (state, settings) = await h.repository.load(h.config, h.now);
    final restored = CounterController(
      config: h.config,
      repository: h.repository,
      state: state,
      settings: settings,
      clock: () => h.now,
    );
    addTearDown(restored.dispose);
    expect(restored.settings.style, CounterStyle.modern);
    expect(restored.settings.vibrationIntensity, 65);
    expect(restored.count, 1);
    expect(restored.target, 220);
    restored.toggleMode();
    expect(restored.count, 1);
  });
  test(
    'complete reset persists defaults and clears all application state',
    () async {
      h.completeDay();
      h.controller.toggleMode();
      h.controller.increment();
      h.controller.toggleStyle();
      h.controller.setIntensity(0);
      await h.controller.resetAll();
      final (state, settings) = await h.repository.load(h.config, h.now);
      expect(state.streak, 0);
      expect(state.lastStreakDate, isNull);
      expect(state.customCount, 0);
      expect(state.customTarget, 100);
      expect(
        state.prayers.values.every(
          (p) => p.counts.values.every((c) => c == 0) && p.completed.isEmpty,
        ),
        isTrue,
      );
      expect(settings.mode, AppMode.prayer);
      expect(settings.style, CounterStyle.classic);
      expect(settings.vibrationIntensity, 40);
    },
  );
  test(
    'restart after days away rolls forward without losing custom data',
    () async {
      h.completeDay();
      h.controller.toggleMode();
      h.controller.increment();
      await h.controller.flush();
      h.now = DateTime(2026, 11, 6);
      final (state, settings) = await h.repository.load(h.config, h.now);
      final restored = CounterController(
        config: h.config,
        repository: h.repository,
        state: state,
        settings: settings,
        clock: () => h.now,
      );
      addTearDown(restored.dispose);
      expect(restored.state.streak, 0);
      expect(restored.state.lastStreakDate, '2026-11-02');
      expect(restored.count, 1);
      expect(
        restored.state.prayers.values.every((p) => p.completed.isEmpty),
        isTrue,
      );
    },
  );
  test('corrupt snapshot recovers to usable fresh state', () async {
    h.store.value = '{broken';
    final (state, settings) = await h.repository.load(h.config, h.now);
    expect(state.date, '2026-11-02');
    expect(state.selectedPrayer, 'fajr');
    expect(settings.vibrationIntensity, 40);
  });
  test('stored values normalized and invalid completions rejected', () async {
    final json = h.controller.state.toJson();
    json['customTarget'] = 2000;
    json['customCount'] = -2;
    json['selectedPrayer'] = 'invalid';
    json['prayers']['fajr'] = {
      'selectedDuaId': 'invalid',
      'counts': {'ayatulkursi': 1, 'subhanallah': -9},
      'completed': ['ayatulkursi', 'subhanallah', 'invalid'],
    };
    final state = AppState.fromJson(h.config, json);
    expect(state.customTarget, 1000);
    expect(state.customCount, 0);
    expect(state.selectedPrayer, 'fajr');
    expect(state.prayers['fajr']!.completed, {'ayatulkursi'});
  });
  test(
    'rapid writes serialize and reset cannot be overwritten by earlier taps',
    () async {
      for (var i = 0; i < 30; i++) {
        h.controller.increment();
      }
      await h.controller.resetAll();
      final json = jsonDecode(h.store.value!);
      expect(json['state']['prayers']['fajr']['counts'], isEmpty);
      expect(h.store.writes.length, 31);
    },
  );
  test('write failure is visible and next successful save recovers', () async {
    h.store.fail = true;
    h.controller.increment();
    await h.controller.flush();
    expect(h.controller.storageError, isNotNull);
    h.store.fail = false;
    h.controller.increment();
    await h.controller.flush();
    expect(h.controller.storageError, isNull);
    expect(
      jsonDecode(
        h.store.value!,
      )['state']['prayers']['fajr']['counts']['subhanallah'],
      2,
    );
  });
  test(
    'real preferences adapter saves one native versioned snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = ProgressRepository(PreferencesStore(prefs));
      await repository.save(
        repository.encode(h.controller.state, h.controller.settings),
      );
      expect(prefs.getKeys(), {PreferencesStore.key});
      final (state, _) = await repository.load(h.config, h.now);
      expect(state.date, '2026-11-02');
    },
  );
}

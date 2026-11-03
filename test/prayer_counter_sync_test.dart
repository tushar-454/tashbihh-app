import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/prayer/prayer_location.dart';
import 'package:tashbihh/core/prayer/prayer_times.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';

import 'prayer_sync_support.dart';
import 'test_support.dart';

void main() {
  late SyncHarness h;
  late CounterController controller;
  setUp(() {
    h = SyncHarness();
  });
  tearDown(() {
    controller.dispose();
  });

  test('synchronized windows and Isha wrap at canonical boundaries', () async {
    await h.sync.load();
    await h.start();
    controller = h.controller();
    final schedule = controller.schedule;
    for (final entry in <int, String?>{
      0: 'isha',
      287: 'isha',
      288: 'fajr',
      364: 'fajr',
      365: null,
      701: null,
      702: 'dhuhr',
      942: 'dhuhr',
      943: 'asr',
      1037: 'asr',
      1038: 'maghrib',
      1114: 'maghrib',
      1115: 'isha',
      1439: 'isha',
    }.entries) {
      h.now = DateTime(2026, 11, 3, 0, entry.key);
      // Use the schedule directly for times before the successful sync instant.
      expect(schedule.activePrayer(h.now), entry.value, reason: '${entry.key}');
    }
    expect(schedule.ended('isha', DateTime(2026, 11, 3, 1)), isFalse);
    expect(schedule.ended('isha', DateTime(2026, 11, 3, 12)), isTrue);
    expect(schedule.ended('isha', DateTime(2026, 11, 3, 23)), isFalse);
    expect(
      schedule.nextTransition(DateTime(2026, 11, 3, 1)),
      DateTime(2026, 11, 3, 4, 48),
    );
    expect(
      schedule.nextTransition(DateTime(2026, 11, 3, 23)),
      DateTime(2026, 11, 4),
    );
  });

  test('success updates selection/availability immediately and preserves progress/custom data', () async {
    h.now = DateTime(2026, 11, 3, 15, 30); // JSON gap, API Dhuhr window.
    await h.sync.load();
    controller = h.controller();
    controller.state.prayers['fajr']!.counts['subhanallah'] = 7;
    controller.state.customCount = 19;
    controller.state.customTarget = 300;
    var changes = 0;
    controller.addListener(() {
      changes++;
    });
    expect(controller.activePrayer, isNull);
    await h.start();
    expect(controller.activePrayer, 'dhuhr');
    expect(controller.state.selectedPrayer, 'dhuhr');
    expect(controller.canCount, isTrue);
    expect(changes, greaterThan(0));
    expect(controller.state.prayers['fajr']!.counts['subhanallah'], 7);
    expect(controller.state.customCount, 19);
    expect(controller.state.customTarget, 300);
    controller.toggleMode();
    expect(controller.increment(), isTrue);
    expect(controller.state.customCount, 20);
  });

  testWidgets('startup remains usable while location is pending', (
    tester,
  ) async {
    h.now = DateTime(2026, 11, 3, 5);
    h.gps.pending = Completer<PrayerCoordinates>();
    await h.sync.load();
    controller = h.controller();
    final device = TestDevice();
    addTearDown(device.dispose);
    await tester.pumpWidget(TasbihApp(controller: controller, device: device));
    await tester.pumpAndSettle();
    expect(h.gps.positions, 1);
    expect(h.api.calls, 0);
    expect(controller.canCount, isTrue);
    expect(controller.increment(), isTrue);
    expect(controller.count, 1);
    h.gps.pending!.complete(PrayerCoordinates(23.81, 90.413));
    await h.sync.synchronize();
    await tester.pumpAndSettle();
    expect(controller.count, 1);
    expect(h.api.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('existing foreground timer updates counters exactly at Sunrise', (
    tester,
  ) async {
    h.now = DateTime(2026, 11, 3, 6, 4, 59);
    await h.sync.load();
    await h.start();
    controller = h.controller();
    controller.startClock();
    expect(controller.canCount, isTrue);
    h.now = DateTime(2026, 11, 3, 6, 5);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.activePrayer, isNull);
    expect(controller.canCount, isFalse);
    expect(controller.increment(), isFalse);
    controller.stopClock();
  });

  testWidgets(
    'foreground midnight timer fetches next date and Isha ends at new Fajr',
    (tester) async {
      h.now = DateTime(2026, 11, 3, 23, 59, 59);
      await h.sync.load();
      await h.start();
      controller = h.controller();
      controller.startClock();
      expect(controller.activePrayer, 'isha');
      controller.state.customCount = 11;
      h.now = DateTime(2026, 11, 4);
      await tester.pump(const Duration(seconds: 1));
      await h.sync.synchronize();
      expect(h.api.calls, 2);
      expect(controller.state.date, '2026-11-04');
      expect(controller.activePrayer, 'isha');
      expect(controller.state.customCount, 11);
      controller.stopClock();
      h.now = DateTime(2026, 11, 4, 4, 48);
      controller.refresh();
      expect(controller.activePrayer, 'fajr');
      expect(controller.state.selectedPrayer, 'fajr');
    },
  );

  test(
    'failed midnight refresh keeps counters on saved times until recovery',
    () async {
      h.now = DateTime(2026, 11, 3, 23);
      await h.sync.load();
      await h.start();
      controller = h.controller();
      expect(controller.activePrayer, 'isha');
      h.api.error = StateError('offline');
      h.now = DateTime(2026, 11, 4);
      controller.refresh();
      expect(controller.schedule, isNot(same(h.config.schedule)));
      expect(controller.activePrayer, 'isha');
      await h.sync.synchronize();
      expect(controller.schedule, isNot(same(h.config.schedule)));
      expect(h.sync.cached!.date, '2026-11-03');
      h.now = DateTime(2026, 11, 4, 4, 45);
      controller.refresh();
      expect(controller.activePrayer, 'isha');
      h.now = DateTime(2026, 11, 4, 4, 48);
      controller.refresh();
      expect(controller.activePrayer, 'fajr');
      expect(controller.canCount, isTrue);
      h.api.error = null;
      await h.start();
      expect(h.sync.cached!.date, '2026-11-04');
      expect(h.api.calls, 3);
    },
  );

  testWidgets(
    'app launch/resume after several days refreshes without duplicate calls',
    (tester) async {
      await h.sync.load();
      controller = h.controller();
      final device = TestDevice();
      addTearDown(device.dispose);
      await tester.pumpWidget(
        TasbihApp(controller: controller, device: device),
      );
      await tester.pumpAndSettle();
      expect(h.api.calls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      h.now = DateTime(2026, 11, 7, 16);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.api.calls, 2);
      expect(controller.activePrayer, 'asr');
      expect(h.sync.cached!.date, '2026-11-07');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.api.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Android clock event rechecks timezone and updates availability',
    (tester) async {
      await h.sync.load();
      controller = h.controller();
      final device = TestDevice();
      addTearDown(device.dispose);
      await tester.pumpWidget(
        TasbihApp(controller: controller, device: device),
      );
      await tester.pumpAndSettle();
      h.zone = zoneFor(h.now, excluding: h.zone);
      device.clockEvents.add(null);
      await tester.pumpAndSettle();
      expect(h.api.calls, 2);
      expect(h.sync.cached!.deviceTimezone, h.zone);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'first-launch explanation has no sync button and declining keeps counting functional',
    (tester) async {
      h.gps.access = PrayerLocationAccess.denied;
      h.now = DateTime(2026, 11, 3, 5);
      await h.sync.load();
      controller = h.controller();
      final device = TestDevice();
      addTearDown(device.dispose);
      await tester.pumpWidget(
        TasbihApp(controller: controller, device: device),
      );
      await tester.pumpAndSettle();
      expect(find.text('Local prayer times'), findsOneWidget);
      expect(
        find.textContaining('never tracked in the background'),
        findsOneWidget,
      );
      expect(find.text('Sync'), findsNothing);
      await tester.tap(find.text('Use configured times'));
      await tester.pumpAndSettle();
      expect(h.gps.requests, 0);
      expect(h.api.calls, 0);
      expect(controller.increment(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

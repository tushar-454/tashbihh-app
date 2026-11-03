import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/prayer/prayer_location.dart';
import 'package:tashbihh/core/prayer/prayer_times.dart';
import 'package:tashbihh/core/prayer/prayer_times_repository.dart';

import 'prayer_sync_support.dart';

void main() {
  late SyncHarness h;
  setUp(() {
    h = SyncHarness();
  });
  tearDown(() {
    h.sync.dispose();
  });

  test(
    'initial launch explains permission once and synchronizes automatically',
    () async {
      h.gps.access = PrayerLocationAccess.denied;
      await h.sync.load();
      expect(h.api.calls, 0);
      await h.start();
      expect(h.explanations, 1);
      expect(h.gps.requests, 1);
      expect(h.gps.positions, 1);
      expect(h.api.calls, 1);
      expect(h.sync.cached!.date, '2026-11-03');
      expect(h.store.writes, hasLength(1));
      expect(h.sync.scheduleFor(h.now), isNot(same(h.config.schedule)));
      expect(h.sync.scheduleFor(h.now).activePrayer(h.now), 'dhuhr');
      expect(h.sync.message, isNull);
    },
  );

  test('today cache loads offline with zero GPS/permission/API calls on repeated launches/resumes', () async {
    await h.repository.save(dailyTimes(h.now, h.zone));
    h.api.error = StateError('offline');
    h.gps.access = PrayerLocationAccess.denied;
    await h.sync.load();
    expect(h.sync.scheduleFor(h.now), isNot(same(h.config.schedule)));
    for (var i = 0; i < 4; i++) {
      await h.start();
      h.sync.suspend();
    }
    expect(h.gps.checks, 0);
    expect(h.gps.positions, 0);
    expect(h.gps.requests, 0);
    expect(h.api.calls, 0);
  });

  test(
    'yesterday cache never overrides JSON; offline failure never overwrites it',
    () async {
      await h.repository.save(
        dailyTimes(h.now.subtract(const Duration(days: 1)), h.zone),
      );
      final previous = h.store.value;
      h.api.error = StateError('offline');
      await h.sync.load();
      expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
      await h.start();
      expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
      expect(h.store.value, previous);
      expect(h.sync.message, contains('configured'));
    },
  );

  for (final access in [
    PrayerLocationAccess.denied,
    PrayerLocationAccess.permanentlyDenied,
  ]) {
    test(
      '$access never prompts repeatedly, but Settings changes recover',
      () async {
        h.gps.access = access;
        h.gps.requestResult = access;
        await h.sync.load();
        await h.start();
        await h.start();
        h.now = h.now.add(const Duration(days: 1));
        h.sync.observeClock(h.now);
        await h.sync.synchronize();
        expect(h.gps.requests, access == PrayerLocationAccess.denied ? 1 : 0);
        expect(h.api.calls, 0);
        expect(h.sync.message, contains('Android Settings'));
        expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
        h.gps.access = PrayerLocationAccess.granted;
        await h.start();
        expect(h.api.calls, 1);
        expect(h.sync.message, isNull);
      },
    );
  }

  test(
    'denied prompt marker survives a new permission handler (app restart)',
    () async {
      h.gps.access = PrayerLocationAccess.denied;
      h.gps.requestResult = PrayerLocationAccess.denied;
      await h.sync.load();
      await h.start();
      final restarted = PrayerLocation(h.gps, h.permissionStore);
      await expectLater(
        restarted.authorize(h.explain, () => true),
        throwsA(isA<PrayerLocationException>()),
      );
      expect(h.explanations, 1);
      expect(h.gps.requests, 1);
    },
  );

  test(
    'declining explanation continues on JSON without a permission prompt',
    () async {
      h.gps.access = PrayerLocationAccess.denied;
      h.explainResult = false;
      await h.sync.load();
      await h.start();
      await h.start();
      expect(h.explanations, 1);
      expect(h.gps.requests, 0);
      expect(h.gps.positions, 0);
      expect(h.api.calls, 0);
    },
  );

  test(
    'permission marker write failure does not show a nonpersistent prompt',
    () async {
      h.gps.access = PrayerLocationAccess.denied;
      h.permissionStore.fail = true;
      await h.sync.load();
      await h.start();
      expect(h.gps.requests, 0);
      expect(h.explanations, 0);
      expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
    },
  );

  test('disabled location services use JSON and recover on resume', () async {
    h.gps.enabled = false;
    await h.sync.load();
    await h.start();
    expect(h.gps.positions, 0);
    expect(h.api.calls, 0);
    expect(h.sync.message, contains('Turn on device Location'));
    h.gps.enabled = true;
    await h.start();
    expect(h.api.calls, 1);
  });

  test(
    'failed sync can retry later without a permanent same-day guard',
    () async {
      h.api.error = TimeoutException('request timed out');
      await h.sync.load();
      await h.start();
      expect(h.api.calls, 1);
      expect(h.sync.cached, isNull);
      h.api.error = null;
      await h.start();
      expect(h.api.calls, 2);
      await h.start();
      expect(h.api.calls, 2);
    },
  );

  testWidgets(
    'failed requests retry at 5 and 30 minutes, then wait for resume',
    (tester) async {
      h.api.error = StateError('offline');
      await h.sync.load();
      await h.start();
      await tester.pump(const Duration(minutes: 4));
      expect(h.api.calls, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(h.api.calls, 2);
      await tester.pump(const Duration(minutes: 30));
      await tester.pump();
      expect(h.api.calls, 3);
      await tester.pump(const Duration(hours: 3));
      expect(h.api.calls, 3);
      h.api.error = null;
      await h.start();
      expect(h.api.calls, 4);
    },
  );

  testWidgets('background cancels retry timers and starts no GPS/API work', (
    tester,
  ) async {
    h.api.error = StateError('offline');
    await h.sync.load();
    await h.start();
    h.sync.suspend();
    h.now = h.now.add(const Duration(days: 3));
    h.sync.observeClock(h.now);
    await tester.pump(const Duration(hours: 2));
    await h.sync.synchronize();
    expect(h.api.calls, 1);
    expect(h.gps.cancellations, greaterThan(0));
    h.api.error = null;
    await h.start();
    expect(h.api.calls, 2);
    expect(h.sync.cached!.date, '2026-11-06');
  });

  test('concurrent launch/resume/date checks share one request', () async {
    final pending = h.gps.pending = Completer<PrayerCoordinates>();
    await h.sync.load();
    h.sync.resume(h.explain);
    final first = h.sync.synchronize();
    final second = h.sync.synchronize();
    expect(first, same(second));
    await Future<void>.delayed(Duration.zero);
    expect(h.gps.positions, 1);
    pending.complete(PrayerCoordinates(23.81, 90.413));
    await Future.wait([first, second]);
    expect(h.api.calls, 1);
  });

  test(
    'minute ticks and counter refreshes do not continuously poll after failure',
    () async {
      h.api.error = StateError('offline');
      await h.sync.load();
      await h.start();
      for (var i = 0; i < 100; i++) {
        h.now = h.now.add(const Duration(seconds: 1));
        h.sync.observeClock(h.now);
      }
      expect(h.api.calls, 1);
      expect(h.gps.positions, 1);
    },
  );

  test(
    'midnight invalidates cache immediately and synchronizes new day',
    () async {
      h.now = DateTime(2026, 11, 3, 23, 59);
      await h.sync.load();
      await h.start();
      expect(h.sync.scheduleFor(h.now).activePrayer(h.now), 'isha');
      h.now = DateTime(2026, 11, 4);
      expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
      h.sync.observeClock(h.now);
      await h.sync.synchronize();
      expect(h.api.calls, 2);
      expect(h.sync.cached!.date, '2026-11-04');
      expect(h.sync.scheduleFor(h.now).activePrayer(h.now), 'isha');
    },
  );

  test('in-flight response from yesterday is discarded, then new date synchronizes', () async {
    h.now = DateTime(2026, 11, 3, 23, 59);
    final previous = dailyTimes(h.now, h.zone);
    final pending = h.api.pending = Completer<PrayerTimes>();
    await h.sync.load();
    h.sync.resume(h.explain);
    final running = h.sync.synchronize();
    await Future<void>.delayed(Duration.zero);
    expect(h.api.calls, 1);
    h.now = DateTime(2026, 11, 4);
    h.sync.observeClock(h.now);
    pending.complete(previous);
    await running;
    await h.sync.synchronize();
    expect(h.api.calls, 2);
    expect(h.store.writes, hasLength(1));
    expect(h.sync.cached!.date, '2026-11-04');
  });

  test(
    'same-offset timezone change detected on resume invalidates old cache',
    () async {
      await h.sync.load();
      await h.start();
      h.zone = zoneFor(h.now, excluding: h.zone);
      await h.start();
      expect(h.api.calls, 2);
      expect(h.sync.cached!.deviceTimezone, h.zone);
    },
  );

  test('cache storage failure keeps old record and allows retry', () async {
    await h.repository.save(
      dailyTimes(h.now.subtract(const Duration(days: 1)), h.zone),
    );
    final previous = h.store.value;
    await h.sync.load();
    h.store.fail = true;
    await h.start();
    expect(h.store.value, previous);
    expect(h.sync.cached!.date, '2026-11-02');
    expect(h.sync.scheduleFor(h.now), same(h.config.schedule));
    h.store.fail = false;
    await h.start();
    expect((await PrayerTimesRepository(h.store).load())!.date, '2026-11-03');
  });
}

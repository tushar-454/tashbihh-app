import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/theme/tasbih_theme.dart';
import 'package:tashbihh/core/notifications/prayer_notifications.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/core/time/prayer_schedule.dart';
import 'package:tashbihh/features/settings/settings_panel.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'test_support.dart';

class ReplacementMemoryStore extends MemoryStore
    implements ReplacementSnapshotStore {
  int replacements = 0;
  @override
  Future<void> writeReplacement(String value) async {
    replacements++;
    await write(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final config = testConfig();

  group('notification plan uses counter windows', () {
    setUpAll(tz_data.initializeTimeZones);
    Map<String, Object> build(
      DateTime now,
      String zone,
      PrayerSchedule schedule,
    ) => NotificationPlan.build(
      now: now,
      zone: zone,
      config: config,
      scheduleFor: (_) => schedule,
    );
    Map<String, dynamic> first(Map<String, Object> plan) =>
        (plan['days'] as List).first as Map<String, dynamic>;

    test('seven dated days use canonical Fajr end and configured grace', () {
      final plan = build(DateTime.utc(2026, 11, 4), 'UTC', config.schedule);
      expect((plan['days'] as List).length, 7);
      expect(first(plan)['date'], '2026-11-04');
      final windows = first(plan)['windows'] as List;
      for (final prayer in config.schedule.prayers) {
        final window = windows.firstWhere((w) => w['id'] == prayer.id);
        expect(
          DateTime.fromMillisecondsSinceEpoch(window['end'], isUtc: true),
          DateTime.utc(
            2026,
            11,
            4,
          ).add(Duration(minutes: config.schedule.endOf(prayer))),
        );
      }
      expect(plan['targets'], contains('dhuhr'));
    });

    test(
      'API early Isha reminders belong to the current calendar progress date',
      () {
        final schedule = PrayerSchedule(config.prayers, earlyIshaEnd: 300);
        final plan = build(DateTime.utc(2026, 11, 4, 1), 'UTC', schedule);
        final day = first(plan);
        final isha = (day['windows'] as List).firstWhere(
          (w) => w['id'] == 'isha',
        );
        expect(isha['start'], DateTime.utc(2026, 11, 4).millisecondsSinceEpoch);
        expect(
          isha['end'],
          DateTime.utc(2026, 11, 4, 5).millisecondsSinceEpoch,
        );
        expect(
          day['ishaEnd'],
          DateTime.utc(2026, 11, 5).millisecondsSinceEpoch,
        );
        expect(
          day['ishaStart'],
          DateTime.utc(2026, 11, 4)
              .add(
                Duration(
                  minutes: schedule.prayers
                      .firstWhere((p) => p.id == 'isha')
                      .start,
                ),
              )
              .millisecondsSinceEpoch,
        );
      },
    );

    test('DST uses each civil date offset without adding 24-hour days', () {
      final plan = build(
        DateTime.utc(2026, 10, 31, 16),
        'America/New_York',
        config.schedule,
      );
      final days = plan['days'] as List;
      expect(
        days[1]['dayEnd'] - days[1]['dayStart'],
        const Duration(hours: 25).inMilliseconds,
      );
      expect(days[2]['date'], '2026-11-02');
      final spring = build(
        DateTime.utc(2026, 3, 7, 16),
        'America/New_York',
        config.schedule,
      );
      final springDays = spring['days'] as List;
      expect(
        springDays[1]['dayEnd'] - springDays[1]['dayStart'],
        const Duration(hours: 23).inMilliseconds,
      );
    });

    test('positive and negative offsets select the device local date', () {
      expect(
        first(
          build(DateTime.utc(2026, 11, 4, 22), 'Asia/Dhaka', config.schedule),
        )['date'],
        '2026-11-05',
      );
      expect(
        first(
          build(
            DateTime.utc(2026, 11, 4, 2),
            'America/New_York',
            config.schedule,
          ),
        )['date'],
        '2026-11-03',
      );
    });

    test('current schedule is evaluated at now, preserving cache freshness validation', () {
      final now = tz.TZDateTime(tz.getLocation('Asia/Dhaka'), 2026, 11, 4, 16);
      DateTime? observed;
      NotificationPlan.build(
        now: now,
        zone: 'Asia/Dhaka',
        config: config,
        scheduleFor: (instant) {
          observed ??= instant;
          return config.schedule;
        },
      );
      expect(observed, now);
    });

    test('schedule end refresh replaces exported instants', () {
      final old = build(DateTime.utc(2026, 11, 4), 'UTC', config.schedule);
      final updated = build(
        DateTime.utc(2026, 11, 4),
        'UTC',
        PrayerSchedule(config.prayers, endGraceMinutes: 10),
      );
      expect(jsonEncode(old), isNot(jsonEncode(updated)));
    });
  });

  group('Android channel and preferences', () {
    const channel = AndroidProgressStore.channel;
    final calls = <MethodCall>[];
    var enabled = true, allowed = false, exact = false;
    var fail = false;
    String? progress;
    setUp(() {
      calls.clear();
      enabled = true;
      allowed = false;
      exact = false;
      fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (fail) throw PlatformException(code: 'unavailable');
            switch (call.method) {
              case 'status':
              case 'requestPermission':
                return {'enabled': enabled, 'allowed': allowed, 'exact': exact};
              case 'setEnabled':
                enabled = call.arguments as bool;
                return null;
              case 'readProgress':
                return progress;
              case 'writeProgress':
                progress = call.arguments['value'];
                return null;
              case 'takeTap':
                return 'dhuhr';
              default:
                return null;
            }
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('permission is requested explicitly and ordinary resume only checks status', () async {
      final n = PrayerNotifications();
      await n.refresh(requestPermission: true);
      expect(n.enabled, isTrue);
      expect(n.allowed, isFalse);
      expect(n.status, contains('Blocked'));
      allowed = true;
      await n.refresh();
      expect(n.status, contains('delay'));
      exact = true;
      await n.refresh();
      expect(n.status, contains('precise'));
      allowed = false;
      await n.refresh();
      expect(n.allowed, isFalse);
      expect(calls.where((c) => c.method == 'requestPermission').length, 1);
      n.dispose();
    });

    test(
      'opt out persists and reenable requests permission through native guard',
      () async {
        final n = PrayerNotifications();
        await n.setEnabled(false);
        expect(n.enabled, isFalse);
        expect(n.status, 'Off');
        await n.refresh();
        expect(n.enabled, isFalse);
        expect(calls.where((c) => c.method == 'requestPermission'), isEmpty);
        await n.setEnabled(true);
        expect(n.enabled, isTrue);
        expect(calls.where((c) => c.method == 'requestPermission').length, 1);
        n.dispose();
      },
    );

    test(
      'duplicate plans are sent only once and changes replace native plan',
      () async {
        final n = PrayerNotifications();
        await n.configure({'version': 1});
        await n.configure({'version': 1});
        await n.configure({'version': 2});
        expect(calls.where((c) => c.method == 'configure').length, 2);
        expect(await n.takeTap(), 'dhuhr');
        n.dispose();
      },
    );

    test(
      'platform failures are handled and failed configure can be retried',
      () async {
        final n = PrayerNotifications();
        fail = true;
        await n.configure({'version': 1});
        expect(n.error, isNotNull);
        expect(n.busy, isFalse);
        expect(await n.takeTap(), isNull);
        fail = false;
        await n.configure({'version': 1});
        expect(n.error, isNull);
        expect(calls.where((c) => c.method == 'configure').length, 2);
        n.dispose();
      },
    );

    test(
      'native store writes original snapshot and marks reset or restore',
      () async {
        final store = AndroidProgressStore();
        await store.write('{"state":"original"}');
        expect(await store.read(), '{"state":"original"}');
        expect(
          calls
              .lastWhere((c) => c.method == 'writeProgress')
              .arguments['replacement'],
          isFalse,
        );
        await store.writeReplacement('{"state":"restored"}');
        expect(calls.last.arguments['replacement'], isTrue);
      },
    );

    testWidgets('settings toggle displays OS block and supports disabling', (
      tester,
    ) async {
      final h = Harness();
      final device = TestDevice();
      final n = PrayerNotifications();
      await n.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: TasbihTheme.data,
          home: Scaffold(
            body: Center(
              child: SettingsPanel(
                controller: h.controller,
                device: device,
                notifications: n,
                onReset: () {},
                onBackup: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Prayer Notifications'), findsOneWidget);
      expect(
        find.text('Blocked in Android notification settings'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('prayer-notifications-toggle')),
      );
      await tester.tap(find.byKey(const Key('prayer-notifications-toggle')));
      await tester.pumpAndSettle();
      expect(n.enabled, isFalse);
      expect(find.text('Off'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      n.dispose();
      h.controller.dispose();
      device.dispose();
    });
  });

  test('replacement repository marks new progress but metadata saves preserve history', () async {
    final store = ReplacementMemoryStore();
    final repository = ProgressRepository(store);
    await repository.replace('first', 'fallback');
    expect(store.replacements, 0);
    await repository.replace('restored', 'first', newProgress: true);
    expect(store.replacements, 1);
    expect(await store.read(), 'restored');
  });
}

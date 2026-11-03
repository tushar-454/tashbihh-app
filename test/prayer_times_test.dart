import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tashbihh/core/prayer/aladhan_client.dart';
import 'package:tashbihh/core/prayer/prayer_times.dart';
import 'package:tashbihh/core/prayer/prayer_times_repository.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:timezone/timezone.dart' as tz;

import 'prayer_sync_support.dart';
import 'test_support.dart';

void main() {
  final now = DateTime(2026, 11, 3, 12);
  final zone = zoneFor(now);
  PrayerTimes parse(Map<String, dynamic> json) => PrayerTimes.fromApi(
    json,
    requestedAt: now,
    coordinates: PrayerCoordinates(23.81, 90.413),
    deviceTimezone: zone,
  );
  test('parses the actual AlAdhan Karachi/Hanafi response for Dhaka', () {
    final json = jsonDecode(
      File('test/fixtures/aladhan_timings.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final dhaka = tz.TZDateTime(tz.getLocation('Asia/Dhaka'), 2026, 11, 3, 12);
    final times = PrayerTimes.fromApi(
      json,
      requestedAt: dhaka,
      coordinates: PrayerCoordinates(23.8103, 90.4125),
      deviceTimezone: 'Asia/Dhaka',
    );
    expect(times.times, {
      'Fajr': 288,
      'Sunrise': 365,
      'Dhuhr': 702,
      'Asr': 943,
      'Maghrib': 1038,
      'Isha': 1115,
    });
    expect(times.calculation.method, 1);
    expect(times.calculation.school, 1);
    expect(times.coordinates.latitude, 23.81);
    expect(times.coordinates.longitude, 90.413);
    expect(times.utcOffsetMinutes, 360);
    expect(PrayerTimes.fromJson(times.toJson()).toJson(), times.toJson());
  });

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'server error': (j) => j['code'] = 500,
    'bad status': (j) => j['status'] = 'ERROR',
    'missing data': (j) => j.remove('data'),
    'missing prayer': (j) => j['data']['timings'].remove('Fajr'),
    'invalid hour': (j) => j['data']['timings']['Fajr'] = '24:00',
    'invalid minute': (j) => j['data']['timings']['Fajr'] = '04:60',
    'invalid string': (j) => j['data']['timings']['Fajr'] = '04:48 bad data',
    'unordered times': (j) => j['data']['timings']['Asr'] = '11:00',
    'wrong date': (j) => j['data']['date']['gregorian']['date'] = '02-11-2026',
    'invalid timestamp': (j) => j['data']['date']['timestamp'] = '0',
    'missing timestamp': (j) => j['data']['date'].remove('timestamp'),
    'unknown timezone': (j) => j['data']['meta']['timezone'] = 'Invalid/Zone',
    'wrong method': (j) => j['data']['meta']['method']['id'] = 3,
    'wrong school': (j) => j['data']['meta']['school'] = 'STANDARD',
    'wrong coordinates': (j) => j['data']['meta']['latitude'] = 0,
  };
  for (final entry in corruptions.entries) {
    test('rejects ${entry.key}', () {
      final json = apiFixture(now, zone);
      entry.value(json);
      expect(() => parse(json), throwsA(anything));
    });
  }
  test(
    'accepts timezone suffixes, rejects device/response offset mismatch',
    () {
      final json = apiFixture(now, zone);
      json['data']['timings']['Fajr'] = '04:48 (+06)';
      expect(parse(json).times['Fajr'], 288);
      final other = tz.TZDateTime(
        tz.getLocation('America/New_York'),
        2026,
        11,
        3,
        12,
      );
      expect(
        () => PrayerTimes.fromApi(
          json,
          requestedAt: other,
          coordinates: PrayerCoordinates(23.81, 90.413),
          deviceTimezone: 'America/New_York',
        ),
        throwsA(anything),
      );
    },
  );
  test(
    'cache is invalid on another day, timezone, method or backwards clock',
    () {
      final times = dailyTimes(now, zone);
      expect(times.validFor(now, zone, const PrayerCalculation()), isTrue);
      expect(
        times.validFor(
          now.add(const Duration(days: 1)),
          zone,
          const PrayerCalculation(),
        ),
        isFalse,
      );
      expect(
        times.validFor(now, 'Changed/Zone', const PrayerCalculation()),
        isFalse,
      );
      expect(
        times.validFor(now, zone, const PrayerCalculation(method: 3)),
        isFalse,
      );
      expect(
        times.validFor(
          now.subtract(const Duration(hours: 1)),
          zone,
          const PrayerCalculation(),
        ),
        isFalse,
      );
    },
  );
  test(
    'HTTP request uses dated HTTPS endpoint and centralized defaults',
    () async {
      final api = AladhanClient(
        clientFactory: () => MockClient((request) async {
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'api.aladhan.com');
          expect(request.url.path, '/v1/timings/03-11-2026');
          expect(request.url.queryParameters, {
            'latitude': '23.81',
            'longitude': '90.413',
            'method': '1',
            'school': '1',
          });
          return http.Response(
            jsonEncode(apiFixture(now, zone)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final times = await api.fetch(
        now: now,
        coordinates: PrayerCoordinates(23.81, 90.413),
        deviceTimezone: zone,
        calculation: const PrayerCalculation(),
      );
      expect(times.date, '2026-11-03');
    },
  );
  test('old cache can be reused only with compatible clocks and settings', () {
    final times = dailyTimes(now, zone);
    final tomorrow = DateTime(2026, 11, 4, 12);
    expect(
      times.canReuseFor(tomorrow, zone, const PrayerCalculation()),
      isTrue,
    );
    expect(times.validFor(tomorrow, zone, const PrayerCalculation()), isFalse);
    expect(
      times.canReuseFor(tomorrow, 'Changed/Zone', const PrayerCalculation()),
      isFalse,
    );
    expect(
      times.canReuseFor(tomorrow, zone, const PrayerCalculation(method: 3)),
      isFalse,
    );
    expect(
      times.canReuseFor(
        now.subtract(const Duration(days: 1)),
        zone,
        const PrayerCalculation(),
      ),
      isFalse,
    );
  });

  for (final zoneName in ['Asia/Dhaka', 'America/New_York']) {
    test('daily freshness changes at local midnight in $zoneName', () {
      final location = tz.getLocation(zoneName);
      final before = tz.TZDateTime(location, 2026, 11, 3, 23, 59, 59);
      final midnight = tz.TZDateTime(location, 2026, 11, 4);
      final times = dailyTimes(before, zoneName);
      expect(
        times.validFor(before, zoneName, const PrayerCalculation()),
        isTrue,
      );
      expect(
        times.validFor(midnight, zoneName, const PrayerCalculation()),
        isFalse,
      );
      expect(
        times.canReuseFor(midnight, zoneName, const PrayerCalculation()),
        isTrue,
      );
      expect(PrayerTimes.apiDate(midnight), '04-11-2026');
      final utcMidnight = tz.TZDateTime.from(
        DateTime.utc(2026, 11, 4),
        location,
      );
      expect(
        dailyTimes(
          tz.TZDateTime(location, 2026, 11, 3),
          zoneName,
        ).validFor(utcMidnight, zoneName, const PrayerCalculation()),
        zoneName == 'America/New_York',
      );
    });
  }

  test('same-date daylight saving offset change invalidates cached times', () {
    final ny = tz.getLocation('America/New_York');
    final before = tz.TZDateTime(ny, 2026, 11, 1, 0, 30);
    final after = tz.TZDateTime(ny, 2026, 11, 1, 2, 30);
    final schedule = dailyTimes(before, 'America/New_York');
    expect(
      schedule.validFor(before, 'America/New_York', const PrayerCalculation()),
      isTrue,
    );
    expect(
      schedule.validFor(after, 'America/New_York', const PrayerCalculation()),
      isFalse,
    );
    expect(
      schedule.canReuseFor(
        after,
        'America/New_York',
        const PrayerCalculation(),
      ),
      isFalse,
    );
  });
  testWidgets('HTTP timeout closes the client and permits a later request', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final client = ClosingClient((_) => pending.future);
    final api = AladhanClient(clientFactory: () => client);
    final request = api.fetch(
      now: now,
      coordinates: PrayerCoordinates(23.81, 90.413),
      deviceTimezone: zone,
      calculation: const PrayerCalculation(),
    );
    final expectation = expectLater(request, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 15));
    await expectation;
    expect(client.closed, isTrue);
    pending.complete(http.Response('{}', 200));
  });
  for (final response in [
    http.Response('unavailable', 503),
    http.Response('{}', 200),
    http.Response('not json', 200),
  ]) {
    test(
      'HTTP rejects server or malformed response ${response.statusCode} ${response.body}',
      () async {
        final api = AladhanClient(
          clientFactory: () => MockClient((_) async => response),
        );
        await expectLater(
          api.fetch(
            now: now,
            coordinates: PrayerCoordinates(23.81, 90.413),
            deviceTimezone: zone,
            calculation: const PrayerCalculation(),
          ),
          throwsA(anything),
        );
      },
    );
  }
  test('separate preference persists through a repository restart without touching progress', () async {
    SharedPreferences.setMockInitialValues({
      PreferencesStore.key: 'existing progress',
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = PrayerTimesRepository(
      PreferencesStore(preferences, storageKey: PrayerTimesRepository.cacheKey),
    );
    await repository.save(dailyTimes(now, zone));
    final restarted = PrayerTimesRepository(
      PreferencesStore(
        await SharedPreferences.getInstance(),
        storageKey: PrayerTimesRepository.cacheKey,
      ),
    );
    expect((await restarted.load())!.toJson(), dailyTimes(now, zone).toJson());
    expect(preferences.getString(PreferencesStore.key), 'existing progress');
  });
  test(
    'invalid persisted data falls back and failed writes retain previous cache',
    () async {
      final store = MemoryStore();
      final repository = PrayerTimesRepository(store);
      for (final raw in [
        'not json',
        '{"version":2}',
        '{"version":1,"schedule":{}}',
      ]) {
        store.value = raw;
        expect(await repository.load(), isNull);
      }
      await repository.save(dailyTimes(now, zone));
      final previous = store.value;
      store.fail = true;
      await expectLater(
        repository.save(dailyTimes(now.add(const Duration(days: 1)), zone)),
        throwsA(anything),
      );
      expect(store.value, previous);
      expect((await repository.load())!.date, '2026-11-03');
    },
  );
}

class ClosingClient extends MockClient {
  ClosingClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

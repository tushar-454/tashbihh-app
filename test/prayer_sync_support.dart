import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/prayer/aladhan_client.dart';
import 'package:tashbihh/core/prayer/prayer_location.dart';
import 'package:tashbihh/core/prayer/prayer_time_sync.dart';
import 'package:tashbihh/core/prayer/prayer_times.dart';
import 'package:tashbihh/core/prayer/prayer_times_repository.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'test_support.dart';

// Keep fake wall clocks portable across development and CI machine timezones.
String zoneFor(DateTime now, {String? excluding}) {
  tz_data.initializeTimeZones();
  return tz.timeZoneDatabase.locations.entries
      .firstWhere(
        (entry) =>
            entry.key != excluding &&
            tz.TZDateTime.from(now, entry.value).timeZoneOffset ==
                now.timeZoneOffset,
      )
      .key;
}

Map<String, dynamic> apiFixture(DateTime now, String zone) {
  final json = jsonDecode(
    File('test/fixtures/aladhan_timings.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  json['data']['date']['gregorian']['date'] = PrayerTimes.apiDate(now);
  json['data']['date']['timestamp'] = '${now.millisecondsSinceEpoch ~/ 1000}';
  json['data']['meta']['timezone'] = zone;
  return json;
}

PrayerTimes dailyTimes(DateTime now, String zone) => PrayerTimes.fromApi(
  apiFixture(now, zone),
  requestedAt: now,
  coordinates: PrayerCoordinates(23.81, 90.413),
  deviceTimezone: zone,
);

class FakeLocation implements PrayerLocationGateway {
  PrayerLocationAccess access = PrayerLocationAccess.granted;
  PrayerLocationAccess requestResult = PrayerLocationAccess.granted;
  bool enabled = true;
  int checks = 0, requests = 0, positions = 0, cancellations = 0;
  Completer<PrayerCoordinates>? pending;
  Object? error;
  @override
  Future<PrayerLocationAccess> checkPermission() async {
    checks++;
    return access;
  }

  @override
  Future<PrayerLocationAccess> requestPermission() async {
    requests++;
    return access = requestResult;
  }

  @override
  Future<bool> servicesEnabled() async => enabled;
  @override
  Future<PrayerCoordinates> currentPosition() async {
    positions++;
    if (error != null) throw error!;
    return pending == null ? PrayerCoordinates(23.81, 90.413) : pending!.future;
  }

  @override
  Future<void> cancelPosition() async {
    cancellations++;
  }
}

class FakePrayerApi implements PrayerTimesApi {
  int calls = 0;
  Object? error;
  Completer<PrayerTimes>? pending;
  @override
  Future<PrayerTimes> fetch({
    required DateTime now,
    required PrayerCoordinates coordinates,
    required String deviceTimezone,
    required PrayerCalculation calculation,
  }) async {
    calls++;
    if (error != null) throw error!;
    final waiting = pending;
    pending = null;
    return waiting?.future ?? dailyTimes(now, deviceTimezone);
  }
}

class SyncHarness {
  SyncHarness({DateTime? date}) {
    now = date ?? DateTime(2026, 11, 3, 12);
    zone = zoneFor(now);
    sync = PrayerTimeSync(
      config: config,
      repository: repository,
      location: PrayerLocation(gps, permissionStore),
      api: api,
      readTimeZone: () async => zone,
      clock: () => now,
    );
  }
  final config = testConfig();
  final store = MemoryStore();
  final permissionStore = MemoryStore();
  final gps = FakeLocation();
  final api = FakePrayerApi();
  late DateTime now;
  late String zone;
  late final repository = PrayerTimesRepository(store);
  late PrayerTimeSync sync;
  int explanations = 0;
  bool explainResult = true;
  Future<bool> explain() async {
    explanations++;
    return explainResult;
  }

  Future<void> start() async {
    sync.resume(explain);
    await sync.synchronize();
  }

  CounterController controller() => CounterController(
    config: config,
    repository: ProgressRepository(MemoryStore()),
    state: AppState.empty(config, now),
    settings: AppSettings(),
    prayerTimes: sync,
    clock: () => now,
  );
}

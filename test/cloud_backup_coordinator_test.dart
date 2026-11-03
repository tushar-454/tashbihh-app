import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/backup/cloud_backup_coordinator.dart';
import 'package:tashbihh/core/backup/cloud_ports.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';

import 'cloud_backup_support.dart';
import 'test_support.dart';

class DelayedCloudStore extends MemoryStore {
  Completer<void>? gate;
  @override
  Future<void> write(String data) async {
    await gate?.future;
    await super.write(data);
  }
}

void main() {
  late Harness h;
  late FakeAuth auth;
  late FakeScheduler scheduler;
  late CloudBackupCoordinator cloud;
  setUp(() {
    h = Harness();
    auth = FakeAuth();
    scheduler = FakeScheduler();
    cloud = CloudBackupCoordinator(
      controller: h.controller,
      auth: auth,
      scheduler: scheduler,
    );
  });
  tearDown(() {
    cloud.dispose();
    h.controller.dispose();
  });
  List<int> backup() => cloud.format.wrap(
    cloud.format.serializer.export(
      h.controller.state,
      h.controller.settings,
      h.now,
    ),
    h.now,
  );
  Future<void> seedB() async {
    h.controller.toggleMode();
    h.controller.setIntensity(75);
    for (var i = 0; i < 7; i++) {
      h.controller.increment();
    }
    auth.drives['b']!.bytes = backup();
    await h.controller.resetAll();
  }

  test(
    'first connection preserves all local progress and creates first backup',
    () async {
      h.controller.increment();
      h.controller.toggleStyle();
      final before = h.controller.state.toJson();
      await cloud.connect();
      expect(h.controller.state.toJson(), before);
      expect(cloud.account!.id, 'a');
      expect(auth.drives['a']!.uploads, 1);
      expect(cloud.lastSuccessfulBackup, h.now.toUtc());
      final saved = cloud.format.validate(auth.drives['a']!.bytes!);
      expect(saved.state(h.config).prayers['fajr']!.counts['subhanallah'], 1);
      expect(saved.settings.toJson(), h.controller.settings.toJson());
      expect(
        utf8.decode(auth.drives['a']!.bytes!),
        isNot(contains('accountId')),
      );
    },
  );

  test('existing backup authoritative; restores settings and counters without uploading', () async {
    await seedB();
    auth.chosen = FakeAuth.b;
    h.controller.increment();
    await cloud.connect();
    expect(h.controller.isCustom, true);
    expect(h.controller.count, 7);
    expect(h.controller.settings.vibrationIntensity, 75);
    expect(auth.drives['b']!.uploads, 0);
    final (state, settings) = await h.repository.load(h.config, h.now);
    expect(state.customCount, 7);
    expect(settings.vibrationIntensity, 75);
    expect(h.repository.cloudMetadata['accountId'], 'b');
  });

  test(
    'connected button immediate backup ignores schedule and unchanged data',
    () async {
      await cloud.connect();
      await cloud.backupNow();
      h.controller.increment();
      await cloud.backupNow();
      expect(auth.drives['a']!.uploads, 3);
      expect(cloud.account!.id, 'a');
    },
  );

  test(
    '12 hour eligibility, unchanged suppression, and foreground retry cadence',
    () async {
      await cloud.connect();
      h.controller.increment();
      h.now = h.now.add(const Duration(hours: 11, minutes: 59));
      await cloud.checkDue();
      expect(auth.drives['a']!.uploads, 1);
      h.now = h.now.add(const Duration(minutes: 1));
      await cloud.checkDue();
      expect(auth.drives['a']!.uploads, 2);
      h.now = h.now.add(const Duration(hours: 12));
      // Keep same day/custom mode for a stable fingerprint below.
      await cloud.checkDue();
      final uploaded = auth.drives['a']!.uploads;
      await cloud.checkDue();
      expect(auth.drives['a']!.uploads, uploaded);
    },
  );

  test('unchanged data avoids automatic upload after 12 hours', () async {
    h.controller.toggleMode();
    await cloud.connect();
    h.now = h.now.add(const Duration(hours: 12));
    await cloud.checkDue();
    expect(auth.drives['a']!.uploads, 1);
    expect(
      cloud.lastSuccessfulBackup,
      h.now.subtract(const Duration(hours: 12)).toUtc(),
    );
  });

  test(
    'scheduler starts on resume, stops on suspend; overdue startup uploads',
    () async {
      await cloud.connect();
      h.controller.increment();
      h.now = h.now.add(const Duration(hours: 13));
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.starts, 1);
      expect(auth.drives['a']!.uploads, 2);
      cloud.suspend();
      expect(scheduler.check, isNull);
      h.controller.increment();
      h.now = h.now.add(const Duration(hours: 13));
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 3);
    },
  );

  test(
    'offline auto backup preserves data and retries after five minutes',
    () async {
      await cloud.connect();
      h.controller.increment();
      final success = cloud.lastSuccessfulBackup;
      auth.drives['a']!.offline = true;
      h.now = h.now.add(const Duration(hours: 12));
      await cloud.checkDue();
      expect(cloud.lastSuccessfulBackup, success);
      expect(h.controller.count, 1);
      final attempts = auth.resumes;
      await cloud.checkDue();
      expect(auth.resumes, attempts);
      auth.drives['a']!.offline = false;
      h.now = h.now.add(const Duration(minutes: 5));
      await cloud.checkDue();
      expect(auth.drives['a']!.uploads, 2);
    },
  );

  test(
    'switch to existing backup never uploads previous account data',
    () async {
      await seedB();
      await cloud.connect();
      h.controller.increment();
      auth.chosen = FakeAuth.b;
      final remote = auth.drives['b']!.bytes;
      await cloud.connect();
      expect(h.controller.count, 7);
      expect(cloud.account!.id, 'b');
      expect(auth.drives['b']!.bytes, remote);
      expect(auth.drives['b']!.uploads, 0);
      await cloud.backupNow();
      expect(auth.drives['a']!.uploads, 1);
      expect(auth.drives['b']!.uploads, 1);
    },
  );

  test(
    'switch to empty account retains local progress and backs it up',
    () async {
      await cloud.connect();
      h.controller.increment();
      auth.chosen = FakeAuth.b;
      await cloud.connect();
      expect(h.controller.count, 1);
      expect(auth.drives['b']!.uploads, 1);
      expect(cloud.account!.id, 'b');
    },
  );

  for (final failure in ['auth', 'corrupt', 'network', 'storage']) {
    test(
      'failed $failure switch preserves previous account and local data',
      () async {
        await cloud.connect();
        h.controller.increment();
        await h.controller.flush();
        final before = h.controller.state.toJson();
        auth.chosen = FakeAuth.b;
        if (failure == 'auth') auth.denied = true;
        if (failure == 'corrupt') auth.drives['b']!.bytes = utf8.encode('{}');
        if (failure == 'network') auth.drives['b']!.offline = true;
        if (failure == 'storage') h.store.fail = true;
        await expectLater(cloud.connect(), throwsA(anything));
        expect(cloud.account!.id, 'a');
        expect(h.controller.state.toJson(), before);
        expect(auth.drives['a']!.uploads, 1);
      },
    );
  }

  test('wrong authenticated identity never uploads across accounts', () async {
    await cloud.connect();
    auth.wrongResume = FakeAuth.b;
    await expectLater(cloud.backupNow(), throwsA(isA<BackupException>()));
    expect(auth.drives['b']!.uploads, 0);
    expect(auth.drives['a']!.uploads, 1);
  });

  test('expired authentication preserves progress and timestamps', () async {
    await cloud.connect();
    h.controller.increment();
    auth.denied = true;
    final before = Map.of(h.repository.cloudMetadata);
    await expectLater(cloud.backupNow(), throwsA(isA<BackupException>()));
    expect(h.controller.count, 1);
    expect(h.repository.cloudMetadata, before);
  });

  test('successful cloud reset deletes only active account, defaults and disconnects', () async {
    await seedB();
    await cloud.connect();
    h.controller.increment();
    await cloud.resetEverything();
    expect(auth.drives['a']!.bytes, isNull);
    expect(auth.drives['b']!.bytes, isNotNull);
    expect(h.controller.count, 0);
    expect(h.controller.settings.vibrationIntensity, 40);
    expect(cloud.account, isNull);
    expect(cloud.lastSuccessfulBackup, isNull);
    expect(h.repository.cloudMetadata, isEmpty);
    h.now = h.now.add(const Duration(days: 2));
    await cloud.checkDue();
    expect(auth.drives['a']!.uploads, 1);
    await expectLater(cloud.backupNow(), throwsA(isA<BackupException>()));
    expect(auth.drives['a']!.bytes, isNull);
  });

  for (final failure in ['delete', 'offline', 'auth']) {
    test(
      'reset $failure preserves data and prevents automatic backup until retry',
      () async {
        await cloud.connect();
        h.controller.increment();
        await h.controller.flush();
        final before = h.controller.state.toJson();
        auth.drives['a']!.deleteFailure = failure == 'delete';
        auth.drives['a']!.offline = failure == 'offline';
        auth.denied = failure == 'auth';
        await expectLater(
          cloud.resetEverything(),
          throwsA(isA<BackupException>()),
        );
        expect(h.controller.state.toJson(), before);
        expect(cloud.resetPending, true);
        h.now = h.now.add(const Duration(hours: 13));
        await cloud.checkDue();
        expect(auth.drives['a']!.uploads, 1);
        auth.drives['a']!.deleteFailure = false;
        auth.drives['a']!.offline = false;
        auth.denied = false;
        await cloud.resetEverything();
        expect(cloud.account, isNull);
      },
    );
  }

  test('local-only reset restores defaults and uses no Google auth', () async {
    h.controller.increment();
    h.controller.toggleStyle();
    await cloud.resetEverything();
    expect(h.controller.count, 0);
    expect(auth.resumes, 0);
    expect(auth.choices, 0);
  });

  test('local commit failure after cloud deletion preserves progress and pending reset for retry', () async {
    await cloud.connect();
    h.controller.increment();
    await h.controller.flush();
    auth.drives['a']!.onDeleted = () {
      h.store.fail = true;
    };
    await expectLater(cloud.resetEverything(), throwsStateError);
    expect(h.controller.count, 1);
    expect(cloud.resetPending, true);
    expect(auth.drives['a']!.bytes, isNull);
    expect(jsonDecode(h.store.value!)['cloud']['resetPending'], true);
    h.store.fail = false;
    auth.drives['a']!.onDeleted = null;
    await cloud.resetEverything();
    expect(h.controller.count, 0);
    expect(cloud.account, isNull);
  });

  test('failed local-only reset leaves local progress active', () async {
    h.controller.increment();
    await h.controller.flush();
    h.store.fail = true;
    await expectLater(cloud.resetEverything(), throwsStateError);
    expect(h.controller.count, 1);
    expect(auth.resumes, 0);
  });

  test('already missing cloud backup allows complete reset', () async {
    await cloud.connect();
    auth.drives['a']!.bytes = null;
    await cloud.resetEverything();
    expect(cloud.account, isNull);
  });

  test(
    'concurrent taps, switch, reset and scheduled operations cannot overlap',
    () async {
      await cloud.connect();
      auth.drives['a']!.gate = Completer<void>();
      final pending = cloud.backupNow();
      await expectLater(cloud.connect(), throwsA(isA<BackupException>()));
      await expectLater(
        cloud.resetEverything(),
        throwsA(isA<BackupException>()),
      );
      await cloud.checkDue();
      expect(
        h.controller.increment(),
        true,
      ); // network backup does not block counters
      auth.drives['a']!.gate!.complete();
      await pending;
      expect(auth.drives['a']!.uploads, 2);
      expect(h.controller.count, 1);
      // Captured fingerprint must not include the count made during the upload.
      h.now = h.now.add(const Duration(hours: 12));
      await cloud.checkDue();
      expect(auth.drives['a']!.uploads, 3);
    },
  );

  test('counting remains available through a slow cloud metadata commit and subsequent writes keep account metadata', () async {
    final store = DelayedCloudStore();
    final repository = ProgressRepository(store);
    final controller = CounterController(
      config: h.config,
      repository: repository,
      state: h.controller.state,
      settings: h.controller.settings,
      clock: () => h.now,
    );
    final coordinator = CloudBackupCoordinator(
      controller: controller,
      auth: auth,
      scheduler: FakeScheduler(),
    );
    addTearDown(() {
      coordinator.dispose();
      controller.dispose();
    });
    await coordinator.connect();
    store.gate = Completer<void>();
    final uploading = coordinator.backupNow();
    await Future<void>.delayed(Duration.zero);
    expect(controller.restoring, false);
    expect(controller.increment(), true);
    store.gate!.complete();
    await uploading;
    await controller.flush();
    expect(controller.count, 1);
    final saved = jsonDecode(store.value!);
    expect(saved['cloud']['accountId'], 'a');
    expect(saved['cloud']['lastBackup'], isNotNull);
    expect(saved['state']['prayers']['fajr']['counts']['subhanallah'], 1);
    h.now = h.now.add(const Duration(hours: 12));
    await coordinator.checkDue();
    expect(auth.drives['a']!.uploads, 3);
  });

  test('restoration blocks mutations; interrupted download leaves durable old account', () async {
    await seedB();
    await cloud.connect();
    h.controller.increment();
    auth.chosen = FakeAuth.b;
    auth.drives['b']!.gate = Completer<void>();
    final switching = cloud.connect();
    await Future<void>.delayed(Duration.zero);
    expect(h.controller.increment(), false);
    final persisted = jsonDecode(h.store.value!);
    expect(persisted['cloud']['accountId'], 'a');
    expect(persisted['state']['customCount'], 0);
    auth.drives['b']!.gate!.complete();
    await switching;
    expect(cloud.account!.id, 'b');
    expect(h.controller.count, 7);
  });

  test('restart after remote deletion and failed local commit blocks backup recreation', () async {
    await cloud.connect();
    h.controller.increment();
    await h.controller.flush();
    // Simulate a process dying after its persisted reset intent and cloud delete.
    await h.controller.commitCloud(
      metadata: {...h.repository.cloudMetadata, 'resetPending': true},
    );
    auth.drives['a']!.bytes = null;
    final repo = ProgressRepository(h.store);
    final (state, settings) = await repo.load(h.config, h.now);
    final restored = CounterController(
      config: h.config,
      repository: repo,
      state: state,
      settings: settings,
      clock: () => h.now,
    );
    final restarted = CloudBackupCoordinator(
      controller: restored,
      auth: auth,
      scheduler: FakeScheduler(),
    );
    addTearDown(() {
      restarted.dispose();
      restored.dispose();
    });
    restarted.resume();
    await restarted.checkDue();
    expect(restored.count, 1);
    expect(restarted.resetPending, true);
    expect(auth.drives['a']!.bytes, isNull);
    await expectLater(restarted.connect(), throwsA(isA<BackupException>()));
    await restarted.resetEverything();
    expect(restored.count, 0);
    expect(restarted.account, isNull);
  });

  test(
    'checksum and future envelope version rejected before local mutation',
    () async {
      final root = jsonDecode(utf8.decode(backup()));
      root['sha256'] = 'incorrect';
      auth.drives['a']!.bytes = utf8.encode(jsonEncode(root));
      h.controller.increment();
      await expectLater(cloud.connect(), throwsA(isA<BackupException>()));
      expect(h.controller.count, 1);
      expect(cloud.account, isNull);
      root['schemaVersion'] = 2;
      expect(
        () => cloud.format.validate(utf8.encode(jsonEncode(root))),
        throwsA(isA<BackupException>()),
      );
    },
  );

  testWidgets(
    'real foreground scheduler checks every five minutes and cancels',
    (tester) async {
      final real = ForegroundBackupScheduler();
      var checks = 0;
      real.start(() async {
        checks++;
      });
      await tester.pump(const Duration(minutes: 5));
      expect(checks, 1);
      await tester.pump(const Duration(minutes: 5));
      expect(checks, 2);
      real.stop();
      await tester.pump(const Duration(minutes: 5));
      expect(checks, 2);
    },
  );
}

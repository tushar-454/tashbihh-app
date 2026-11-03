import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/backup/cloud_backup_coordinator.dart';
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
  late CloudBackupCoordinator cloud;
  setUp(() {
    h = Harness();
    auth = FakeAuth();
    cloud = CloudBackupCoordinator(controller: h.controller, auth: auth);
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

  test('elapsed time and ordinary resume never schedule an upload', () async {
    await cloud.connect();
    h.controller.toggleMode();
    h.controller.increment();
    for (final hours in [12, 24, 48]) {
      h.now = h.now.add(Duration(hours: hours));
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      h.controller.refresh();
      expect(auth.drives['a']!.uploads, 1);
    }
  });

  test('each close uploads once even if data is unchanged', () async {
    await cloud.connect();
    for (var i = 0; i < 3; i++) {
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      cloud.suspend();
      cloud.suspend();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, i + 2);
      expect(
        h.repository.cloudMetadata.containsKey('closeBackupPending'),
        false,
      );
    }
  });

  test('closing during an older upload queues the latest snapshot', () async {
    await cloud.connect();
    cloud.resume();
    auth.drives['a']!.gate = Completer<void>();
    final uploading = cloud.backupNow();
    await Future<void>.delayed(Duration.zero);
    h.controller.increment();
    cloud.suspend();
    cloud.suspend();
    auth.drives['a']!.gate!.complete();
    await uploading;
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 3);
    final saved = cloud.format
        .validate(auth.drives['a']!.bytes!)
        .state(h.config);
    expect(saved.prayers['fajr']!.counts['subhanallah'], 1);
    expect(h.repository.cloudMetadata.containsKey('closeBackupPending'), false);
  });

  test(
    'another close during metadata commit retains the newer snapshot',
    () async {
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
      );
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      await coordinator.connect();
      coordinator.resume();
      store.gate = Completer<void>();
      coordinator.suspend();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      coordinator.resume();
      controller.increment();
      coordinator.suspend();
      expect(repository.cloudMetadata['closeBackupPending'], 2);
      store.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      await controller.flush();
      expect(auth.drives['a']!.uploads, 3);
      final saved = cloud.format
          .validate(auth.drives['a']!.bytes!)
          .state(h.config);
      expect(saved.prayers['fajr']!.counts['subhanallah'], 1);
      expect(repository.cloudMetadata.containsKey('closeBackupPending'), false);
      expect(jsonDecode(store.value!)['cloud']['closeBackupPending'], isNull);
    },
  );

  test('interrupted close upload is recovered on the next launch', () async {
    await cloud.connect();
    cloud.resume();
    h.controller.increment();
    auth.drives['a']!.offline = true;
    cloud.suspend();
    await Future<void>.delayed(Duration.zero);
    await h.controller.flush();
    final repository = ProgressRepository(h.store);
    final (state, settings) = await repository.load(h.config, h.now);
    final controller = CounterController(
      config: h.config,
      repository: repository,
      state: state,
      settings: settings,
      clock: () => h.now,
    );
    final restarted = CloudBackupCoordinator(
      controller: controller,
      auth: auth,
    );
    addTearDown(() {
      restarted.dispose();
      controller.dispose();
    });
    auth.drives['a']!.offline = false;
    restarted.resume();
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 2);
    expect(auth.drives['a']!.downloads, 1);
    expect(repository.cloudMetadata.containsKey('closeBackupPending'), false);
    final saved = cloud.format
        .validate(auth.drives['a']!.bytes!)
        .state(h.config);
    expect(saved.prayers['fajr']!.counts['subhanallah'], 1);
  });

  Future<void> prepareStreakCompletion({
    bool missingEarlierPrayer = false,
  }) async {
    for (final prayer in h.config.prayers) {
      h.now = DateTime(2026, 11, 2, prayer.start ~/ 60, prayer.start % 60);
      h.controller.refresh();
      final required = missingEarlierPrayer && prayer.id == 'fajr' ? 2 : 3;
      for (final (index, dua)
          in h.config.forPrayer(prayer.id).take(required).indexed) {
        h.controller.selectDua(dua.id);
        final remaining = prayer.id == 'isha' && index == 2 ? 1 : 0;
        for (var i = 0; i < dua.target - remaining; i++) {
          h.controller.increment();
        }
      }
    }
    expect(h.controller.state.streak, 0);
    expect(h.controller.count, h.controller.target - 1);
    await cloud.connect();
    cloud.resume();
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'third Isha dua earns one streak day and immediately backs up once',
    () async {
      await prepareStreakCompletion();
      expect(auth.drives['a']!.uploads, 1);
      expect(h.controller.increment(), true);
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.state.streak, 1);
      expect(auth.drives['a']!.uploads, 2);
      final saved = cloud.format
          .validate(auth.drives['a']!.bytes!)
          .state(h.config);
      expect(saved.streak, 1);
      expect(saved.lastStreakDate, '2026-11-02');
      expect(saved.prayers.values.every((p) => p.completed.length >= 3), true);
      expect(
        h.repository.cloudMetadata.containsKey('streakEarnedPending'),
        false,
      );
      expect(
        jsonDecode(h.store.value!)['cloud']['streakEarnedPending'],
        isNull,
      );

      h.controller.refresh();
      h.controller.selectDua(h.config.forPrayer('isha')[3].id);
      h.controller.increment();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.state.streak, 1);
      expect(auth.drives['a']!.uploads, 2);

      h.now = DateTime(2026, 11, 3, 5);
      h.controller.refresh();
      h.completeDay();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.state.streak, 2);
      expect(auth.drives['a']!.uploads, 3);
      expect(
        cloud.format.validate(auth.drives['a']!.bytes!).state(h.config).streak,
        2,
      );
    },
  );

  test('three Isha duas without three in every earlier prayer do not trigger a backup', () async {
    await prepareStreakCompletion(missingEarlierPrayer: true);
    h.controller.increment();
    await Future<void>.delayed(Duration.zero);
    expect(h.controller.state.prayers['isha']!.completed.length, 3);
    expect(h.controller.state.streak, 0);
    expect(auth.drives['a']!.uploads, 1);
    expect(
      h.repository.cloudMetadata.containsKey('streakEarnedPending'),
      false,
    );
  });

  for (final delayed in ['network', 'metadata']) {
    test(
      'streak earned during an older $delayed operation uploads a fresh snapshot',
      () async {
        await prepareStreakCompletion();
        await h.controller.flush();
        final store = DelayedCloudStore()..value = h.store.value;
        final repository = ProgressRepository(store);
        final (state, settings) = await repository.load(h.config, h.now);
        final controller = CounterController(
          config: h.config,
          repository: repository,
          state: state,
          settings: settings,
          clock: () => h.now,
        );
        final coordinator = CloudBackupCoordinator(
          controller: controller,
          auth: auth,
        );
        addTearDown(() {
          coordinator.dispose();
          controller.dispose();
        });
        coordinator.resume();
        final gate = Completer<void>();
        if (delayed == 'network') {
          auth.drives['a']!.gate = gate;
        } else {
          store.gate = gate;
        }
        final uploading = coordinator.backupNow();
        await Future<void>.delayed(Duration.zero);
        controller.increment();
        expect(repository.cloudMetadata['streakEarnedPending'], '2026-11-02');
        gate.complete();
        await uploading;
        await Future<void>.delayed(Duration.zero);
        await controller.flush();
        expect(auth.drives['a']!.uploads, 3);
        final saved = cloud.format
            .validate(auth.drives['a']!.bytes!)
            .state(h.config);
        expect(saved.streak, 1);
        expect(saved.prayers['isha']!.completed.length, 3);
        expect(
          repository.cloudMetadata.containsKey('streakEarnedPending'),
          false,
        );
        expect(
          jsonDecode(store.value!)['cloud']['streakEarnedPending'],
          isNull,
        );
      },
    );
  }

  test(
    'offline earned streak remains pending and backs up once after restart',
    () async {
      await prepareStreakCompletion();
      auth.drives['a']!.offline = true;
      h.controller.increment();
      await Future<void>.delayed(Duration.zero);
      await h.controller.flush();
      expect(h.controller.state.streak, 1);
      expect(
        jsonDecode(h.store.value!)['cloud']['streakEarnedPending'],
        '2026-11-02',
      );
      final attempts = auth.resumes;
      h.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(auth.resumes, attempts);

      final repository = ProgressRepository(h.store);
      final (state, settings) = await repository.load(h.config, h.now);
      final controller = CounterController(
        config: h.config,
        repository: repository,
        state: state,
        settings: settings,
        clock: () => h.now,
      );
      final restarted = CloudBackupCoordinator(
        controller: controller,
        auth: auth,
      );
      addTearDown(() {
        restarted.dispose();
        controller.dispose();
      });
      auth.drives['a']!.offline = false;
      restarted.resume();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      expect(
        cloud.format.validate(auth.drives['a']!.bytes!).state(h.config).streak,
        1,
      );
      expect(
        repository.cloudMetadata.containsKey('streakEarnedPending'),
        false,
      );
      controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
    },
  );

  Future<void> prepareMissedDay() async {
    h.completeDay();
    h.now = DateTime(2026, 11, 3, 5);
    h.controller.refresh();
    // Every prayer except Isha meets the minimum; Isha has only two duas.
    for (final prayer in h.config.prayers) {
      h.now = DateTime(2026, 11, 3, prayer.start ~/ 60, prayer.start % 60);
      h.controller.refresh();
      final required = prayer.id == 'isha' ? 2 : 3;
      for (final dua in h.config.forPrayer(prayer.id).take(required)) {
        h.controller.selectDua(dua.id);
        for (var i = 0; i < dua.target; i++) {
          h.controller.increment();
        }
      }
    }
    h.controller.toggleMode();
    h.controller.increment();
    h.controller.setIntensity(75);
    h.now = DateTime(2026, 11, 3, 23, 59);
    h.controller.refresh();
    expect(h.controller.state.streak, 1);
    await cloud.connect();
  }

  void expectResetBackup() {
    final saved = cloud.format.validate(auth.drives['a']!.bytes!);
    final state = saved.state(h.config);
    expect(state.date, '2026-11-04');
    expect(state.streak, 0);
    expect(state.lastStreakDate, '2026-11-02');
    for (final prayer in state.prayers.values) {
      expect(prayer.completed, isEmpty);
      expect(prayer.counts.values.every((count) => count == 0), true);
    }
    expect(state.customCount, 1);
    expect(saved.settings.vibrationIntensity, 75);
  }

  test('missed prayer resets streak and immediately uploads all cleared daily data', () async {
    await prepareMissedDay();
    cloud.resume();
    await Future<void>.delayed(Duration.zero);
    h.now = DateTime(2026, 11, 4);
    h.controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 2);
    expectResetBackup();
    expect(h.repository.cloudMetadata.containsKey('dailyResetPending'), false);
    expect(jsonDecode(h.store.value!)['cloud']['dailyResetPending'], isNull);
    await cloud.retryPending();
    expect(auth.drives['a']!.uploads, 2);
  });

  test('successful day preserves streak without an automatic upload', () async {
    h.completeDay();
    h.now = DateTime(2026, 11, 2, 23, 59);
    await cloud.connect();
    cloud.resume();
    await Future<void>.delayed(Duration.zero);
    h.now = DateTime(2026, 11, 3);
    h.controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 1);
    expect(h.controller.state.streak, 1);
    expect(
      h.controller.state.prayers.values.every((p) => p.completed.isEmpty),
      true,
    );
    expect(h.repository.cloudMetadata.containsKey('dailyResetPending'), false);
  });

  test('offline streak loss survives restart and retries on launch', () async {
    await prepareMissedDay();
    auth.drives['a']!.offline = true;
    h.now = DateTime(2026, 11, 4);
    cloud.resume();
    await Future<void>.delayed(Duration.zero);
    await h.controller.flush();
    expect(h.controller.state.streak, 0);
    expect(
      jsonDecode(h.store.value!)['cloud']['dailyResetPending'],
      '2026-11-04',
    );
    final attempts = auth.resumes;
    h.controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(auth.resumes, attempts);

    final repository = ProgressRepository(h.store);
    final (state, settings) = await repository.load(h.config, h.now);
    final controller = CounterController(
      config: h.config,
      repository: repository,
      state: state,
      settings: settings,
      clock: () => h.now,
    );
    final restarted = CloudBackupCoordinator(
      controller: controller,
      auth: auth,
    );
    addTearDown(() {
      restarted.dispose();
      controller.dispose();
    });
    auth.drives['a']!.offline = false;
    restarted.resume();
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 2);
    expectResetBackup();
    expect(repository.cloudMetadata.containsKey('dailyResetPending'), false);
  });

  test(
    'startup rollover before coordinator attaches is immediately backed up',
    () async {
      await prepareMissedDay();
      await h.controller.flush();
      h.now = DateTime(2026, 11, 4);
      final repository = ProgressRepository(h.store);
      final (state, settings) = await repository.load(h.config, h.now);
      final controller = CounterController(
        config: h.config,
        repository: repository,
        state: state,
        settings: settings,
        clock: () => h.now,
      );
      expect(controller.state.streak, 0);
      final restarted = CloudBackupCoordinator(
        controller: controller,
        auth: auth,
      );
      addTearDown(() {
        restarted.dispose();
        controller.dispose();
      });
      restarted.resume();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      expectResetBackup();
    },
  );

  test(
    'failed streak loss retries on resume without repeated listener uploads',
    () async {
      await prepareMissedDay();
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      auth.drives['a']!.offline = true;
      h.now = DateTime(2026, 11, 4);
      h.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final attempts = auth.resumes;
      auth.drives['a']!.offline = false;
      h.now = h.now.add(const Duration(minutes: 4));
      h.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(auth.resumes, attempts);
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      expectResetBackup();
    },
  );

  test(
    'rollover during an older upload triggers a second immediate upload',
    () async {
      await prepareMissedDay();
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      auth.drives['a']!.gate = Completer<void>();
      final uploading = cloud.backupNow();
      await Future<void>.delayed(Duration.zero);
      h.now = DateTime(2026, 11, 4);
      h.controller.refresh();
      expect(h.repository.cloudMetadata['dailyResetPending'], '2026-11-04');
      auth.drives['a']!.gate!.complete();
      await uploading;
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 3);
      expectResetBackup();
      expect(
        h.repository.cloudMetadata.containsKey('dailyResetPending'),
        false,
      );
    },
  );

  test(
    'rollover during metadata storage retains pending reset and uploads again',
    () async {
      await prepareMissedDay();
      await h.controller.flush();
      final store = DelayedCloudStore()..value = h.store.value;
      final repository = ProgressRepository(store);
      final (state, settings) = await repository.load(h.config, h.now);
      final controller = CounterController(
        config: h.config,
        repository: repository,
        state: state,
        settings: settings,
        clock: () => h.now,
      );
      final coordinator = CloudBackupCoordinator(
        controller: controller,
        auth: auth,
      );
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });
      coordinator.resume();
      await Future<void>.delayed(Duration.zero);
      store.gate = Completer<void>();
      final uploading = coordinator.backupNow();
      await Future<void>.delayed(Duration.zero);
      // Drive has accepted yesterday's payload; its metadata write is blocked.
      expect(auth.drives['a']!.uploads, 2);
      h.now = DateTime(2026, 11, 4);
      controller.refresh();
      store.gate!.complete();
      await uploading;
      await Future<void>.delayed(Duration.zero);
      await controller.flush();
      expect(auth.drives['a']!.uploads, 3);
      expectResetBackup();
      expect(repository.cloudMetadata.containsKey('dailyResetPending'), false);
      expect(jsonDecode(store.value!)['state']['date'], '2026-11-04');
      expect(jsonDecode(store.value!)['cloud']['dailyResetPending'], isNull);
    },
  );

  test('historical restore immediately uploads normalized zero streak and cleared prayers', () async {
    h.completeDay();
    auth.drives['a']!.bytes = backup();
    h.now = DateTime(2026, 11, 4);
    cloud.resume();
    await cloud.connect();
    await Future<void>.delayed(Duration.zero);
    expect(auth.drives['a']!.uploads, 1);
    final saved = cloud.format
        .validate(auth.drives['a']!.bytes!)
        .state(h.config);
    expect(saved.date, '2026-11-04');
    expect(saved.streak, 0);
    expect(saved.prayers.values.every((p) => p.completed.isEmpty), true);
    expect(saved.restoredDay!['streak'], 1);
    expect(h.repository.cloudMetadata.containsKey('dailyResetPending'), false);
  });

  test(
    'close uploads the latest counters and settings to the current account',
    () async {
      await cloud.connect();
      cloud.resume();
      h.controller.toggleMode();
      h.controller.increment();
      h.controller.setIntensity(75);
      cloud.suspend();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      expect(auth.drives['b']!.uploads, 0);
      final saved = cloud.format.validate(auth.drives['a']!.bytes!);
      expect(saved.state(h.config).customCount, 1);
      expect(saved.settings.vibrationIntensity, 75);
    },
  );

  test(
    'failed close backup remains pending and resumes with latest data',
    () async {
      await cloud.connect();
      cloud.resume();
      h.controller.increment();
      final success = cloud.lastSuccessfulBackup;
      auth.drives['a']!.offline = true;
      cloud.suspend();
      await Future<void>.delayed(Duration.zero);
      await h.controller.flush();
      expect(cloud.lastSuccessfulBackup, success);
      expect(jsonDecode(h.store.value!)['cloud']['closeBackupPending'], 1);
      final attempts = auth.resumes;
      h.controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(auth.resumes, attempts);
      auth.drives['a']!.offline = false;
      h.controller.increment();
      cloud.resume();
      await Future<void>.delayed(Duration.zero);
      expect(auth.drives['a']!.uploads, 2);
      final saved = cloud.format
          .validate(auth.drives['a']!.bytes!)
          .state(h.config);
      expect(saved.prayers['fajr']!.counts['subhanallah'], 2);
      expect(
        h.repository.cloudMetadata.containsKey('closeBackupPending'),
        false,
      );
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
    await cloud.retryPending();
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
        await cloud.retryPending();
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
    'concurrent taps, switch, reset and automatic operations cannot overlap',
    () async {
      await cloud.connect();
      auth.drives['a']!.gate = Completer<void>();
      final pending = cloud.backupNow();
      await expectLater(cloud.connect(), throwsA(isA<BackupException>()));
      await expectLater(
        cloud.resetEverything(),
        throwsA(isA<BackupException>()),
      );
      await cloud.retryPending();
      expect(
        h.controller.increment(),
        true,
      ); // network backup does not block counters
      auth.drives['a']!.gate!.complete();
      await pending;
      expect(auth.drives['a']!.uploads, 2);
      expect(h.controller.count, 1);
      // A later explicit tap captures the count made during the upload.
      await cloud.backupNow();
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
    await coordinator.backupNow();
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
    final restarted = CloudBackupCoordinator(controller: restored, auth: auth);
    addTearDown(() {
      restarted.dispose();
      restored.dispose();
    });
    restarted.resume();
    await restarted.retryPending();
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

  testWidgets('no periodic backup timer runs while the app stays open', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await cloud.connect();
      cloud.resume();
      h.controller.increment();
    });
    await tester.pump(const Duration(hours: 48));
    expect(auth.drives['a']!.uploads, 1);
    expect(auth.resumes, 0);
  });
}

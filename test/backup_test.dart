import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';

import 'test_support.dart';

class FailingCommitStore extends MemoryStore {
  bool failAfterWrite = false;
  Completer<void>? gate;
  @override
  Future<void> write(String data) async {
    if (gate != null) await gate!.future;
    await super.write(data);
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('Simulated post-write failure');
    }
  }
}

void main() {
  late Harness h;
  late BackupSerializer serializer;
  setUp(() {
    h = Harness();
    serializer = BackupSerializer(h.config);
  });
  tearDown(() => h.controller.dispose());
  List<int> bytes() =>
      serializer.export(h.controller.state, h.controller.settings, h.now);
  Map<String, dynamic> json() => jsonDecode(utf8.decode(bytes()));
  ValidatedBackup validate(Map<String, dynamic> root) =>
      serializer.validate(utf8.encode(jsonEncode(root)));

  test('exports complete UTF-8 versioned current state and settings', () {
    h.completeDay();
    h.controller.toggleMode();
    h.controller.setCustomTarget(240);
    h.controller.increment();
    h.controller.toggleStyle();
    h.controller.setIntensity(65);
    final root = json();
    expect(root['format'], 'tasbih_backup');
    expect(root['schemaVersion'], 1);
    expect(root['exportedAt'], endsWith('Z'));
    expect(root['appVersion'], '1.0.0');
    expect(root['data']['state'], h.controller.state.toJson());
    expect(root['data']['settings'], h.controller.settings.toJson());
    final imported = serializer.validate(bytes());
    expect(imported.state(h.config).streak, 1);
    expect(imported.state(h.config).lastStreakDate, '2026-11-02');
    expect(imported.settings.toJson(), h.controller.settings.toJson());
    expect(
      imported
          .state(h.config)
          .prayers
          .values
          .every((p) => p.completed.length == 3),
      isTrue,
    );
  });

  test('same-day export/import restores equivalent normalized state without duplicate streak', () async {
    h.completeDay();
    h.controller.toggleMode();
    h.controller.increment();
    final backup = serializer.validate(bytes());
    final expected = backup.state(h.config).toJson();
    await h.controller.resetAll();
    await h.controller.restore(backup);
    expect(h.controller.state.toJson(), expected);
    expect(h.controller.settings.toJson(), backup.settings.toJson());
    h.controller.refresh();
    await h.controller.restore(backup);
    expect(h.controller.state.streak, 1);
    final (disk, settings) = await h.repository.load(h.config, h.now);
    expect(disk.toJson(), expected);
    expect(settings.toJson(), backup.settings.toJson());
  });

  for (final days in [1, 7, 30]) {
    test(
      'restore $days-day-old backup retains history and uses existing daily rules',
      () async {
        h.completeDay();
        h.controller.toggleMode();
        h.controller.increment();
        final backup = serializer.validate(bytes());
        h.now = DateTime(2026, 11, 2 + days, 12);
        await h.controller.restore(backup);
        expect(h.controller.state.date, dateKey(h.now));
        expect(h.controller.state.streak, days == 1 ? 1 : 0);
        expect(h.controller.state.lastStreakDate, '2026-11-02');
        expect(
          h.controller.state.prayers.values.every((p) => p.completed.isEmpty),
          isTrue,
        );
        expect(h.controller.state.restoredDay!['date'], '2026-11-02');
        expect(h.controller.state.restoredDay!['streak'], 1);
        expect(
          h.controller.state.restoredDay!['prayers']['fajr']['completed'],
          hasLength(3),
        );
        expect(h.controller.state.customCount, 1);
        final again = serializer.validate(bytes()).state(h.config);
        expect(again.restoredDay, h.controller.state.restoredDay);
      },
    );
  }

  test('future dated backup rejected without modifying active state', () async {
    final backup = serializer.validate(bytes());
    h.now = DateTime(2026, 11, 1, 5);
    h.controller.refresh();
    final before = h.controller.state.toJson();
    await expectLater(
      h.controller.restore(backup),
      throwsA(isA<BackupException>()),
    );
    expect(h.controller.state.toJson(), before);
  });

  test('fresh installation recovers all state from external bytes', () async {
    h.completeDay();
    h.controller.toggleMode();
    h.controller.increment();
    h.controller.toggleStyle();
    final externalFile = bytes();
    final store = MemoryStore();
    final repo = ProgressRepository(store);
    final (state, settings) = await repo.load(h.config, h.now);
    final fresh = CounterController(
      config: h.config,
      repository: repo,
      state: state,
      settings: settings,
      clock: () => h.now,
    );
    addTearDown(fresh.dispose);
    await fresh.restore(serializer.validate(externalFile));
    expect(fresh.state.streak, 1);
    expect(fresh.count, 1);
    expect(fresh.settings.style, CounterStyle.modern);
    expect(store.value, isNotNull);
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'wrong format': (j) => j['format'] = 'something_else',
    'future version': (j) => j['schemaVersion'] = 2,
    'old unsupported version': (j) => j['schemaVersion'] = 0,
    'missing data': (j) => j.remove('data'),
    'missing state date': (j) => j['data']['state'].remove('date'),
    'invalid calendar date': (j) => j['data']['state']['date'] = '2026-02-30',
    'invalid timestamp': (j) => j['exportedAt'] = '2026-11-02T99:00:00Z',
    'ambiguous timestamp': (j) => j['exportedAt'] = '2026-11-02T05:00:00',
    'negative prayer count': (j) =>
        j['data']['state']['prayers']['fajr']['counts']['subhanallah'] = -1,
    'fractional count': (j) => j['data']['state']['customCount'] = 0.5,
    'missing prayer': (j) => j['data']['state']['prayers'].remove('isha'),
    'invalid completion': (j) =>
        j['data']['state']['prayers']['fajr']['completed'] = ['ayatulkursi'],
    'invalid selected dua': (j) =>
        j['data']['state']['prayers']['fajr']['selectedDuaId'] = 'unknown',
    'negative streak': (j) => j['data']['state']['streak'] = -1,
    'missing streak date': (j) => j['data']['state'].remove('lastStreakDate'),
    'future streak date': (j) =>
        j['data']['state']['lastStreakDate'] = '2026-11-03',
    'custom overflow': (j) => j['data']['state']['customCount'] = 101,
    'bad settings': (j) => j['data']['settings']['style'] = 'unknown',
    'missing settings': (j) => j['data'].remove('settings'),
    'bad vibration': (j) => j['data']['settings']['vibrationIntensity'] = 42,
    'bad history': (j) => j['data']['state']['restoredDay'] = {},
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without changing stored progress', () async {
      h.controller.increment();
      await h.controller.flush();
      final before = h.store.value;
      final root = json();
      entry.value(root);
      expect(() => validate(root), throwsA(isA<BackupException>()));
      expect(h.store.value, before);
      expect(h.controller.count, 1);
    });
  }
  test('malformed JSON, UTF-8 and oversized files rejected', () {
    for (final data in [
      utf8.encode('{broken'),
      [255, 254],
      List.filled(BackupSerializer.maxBytes + 1, 32),
    ]) {
      expect(() => serializer.validate(data), throwsA(isA<BackupException>()));
    }
  });
  test('validation cannot award missing streak evaluation', () {
    h.completeDay();
    final root = json();
    root['data']['state']['lastStreakDate'] = null;
    root['data']['state']['streak'] = 0;
    expect(() => validate(root), throwsA(isA<BackupException>()));
  });
  test('candidate is detached from preview mutations', () {
    final backup = serializer.validate(bytes());
    backup.data['state']['customCount'] = 99;
    backup.state(h.config).customCount = 55;
    expect(backup.state(h.config).customCount, 0);
  });
  test('failed commit after a write rolls disk and memory back; counting blocked during commit', () async {
    final store = FailingCommitStore();
    final repo = ProgressRepository(store);
    final controller = CounterController(
      config: h.config,
      repository: repo,
      state: AppState.empty(h.config, h.now),
      settings: AppSettings(),
      clock: () => h.now,
    );
    addTearDown(controller.dispose);
    controller.increment();
    await controller.flush();
    final before = store.value;
    final backup = serializer.validate(bytes());
    store.failAfterWrite = true;
    store.gate = Completer<void>();
    final restoring = controller.restore(backup);
    expect(controller.increment(), isFalse);
    controller.toggleMode();
    expect(controller.isCustom, isFalse);
    final assertion = expectLater(restoring, throwsStateError);
    store.gate!.complete();
    await assertion;
    expect(store.value, before);
    expect(controller.count, 1);
    expect(controller.restoring, isFalse);
  });
  test('permanent write failure never reports restore success or changes live data', () async {
    h.controller.increment();
    await h.controller.flush();
    final before = h.store.value;
    h.store.fail = true;
    await expectLater(
      h.controller.restore(serializer.validate(bytes())),
      throwsStateError,
    );
    expect(h.store.value, before);
    expect(h.controller.count, 1);
  });
}

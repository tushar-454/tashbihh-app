import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/platform/backup_documents.dart';

import 'test_support.dart';

void main() {
  late Harness h;
  late TestDevice device;
  Uint8List? selected;
  bool exportResult = true;
  bool fileError = false;
  Map<dynamic, dynamic>? exported;
  Completer<bool>? pendingExport;
  void initialize() {
    h = Harness();
    device = TestDevice();
    selected = null;
    exported = null;
    pendingExport = null;
    exportResult = true;
    fileError = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupDocuments.channel, (call) async {
          if (fileError) {
            throw PlatformException(
              code: 'document',
              message: 'Provider access denied',
            );
          }
          if (call.method == 'open') return selected;
          exported = call.arguments as Map;
          return pendingExport == null ? exportResult : pendingExport!.future;
        });
  }

  void workflow(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      initialize();
      await body(tester);
    });
  }

  tearDown(() {
    h.controller.dispose();
    device.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupDocuments.channel, null);
  });
  Future<void> launch(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      TasbihApp(controller: h.controller, device: device),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-toggle')));
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Uint8List backup() =>
      BackupSerializer(h.config)
          .export(h.controller.state, h.controller.settings, h.now);

  workflow(
    'Settings actions export complete JSON with suggested filename and success',
    (tester) async {
      h.controller.increment();
      await launch(tester);
      expect(find.text('Export Backup'), findsOneWidget);
      expect(find.text('Import Backup'), findsOneWidget);
      await action(tester, 'export-backup');
      expect(exported!['filename'], 'tasbih-backup-2026-11-02-05-00.json');
      final root = jsonDecode(utf8.decode(exported!['bytes'] as Uint8List));
      expect(
        root['data']['state']['prayers']['fajr']['counts']['subhanallah'],
        1,
      );
      expect(find.text('Backup saved successfully.'), findsOneWidget);
    },
  );
  workflow('export cancellation has no success notification', (tester) async {
    exportResult = false;
    await launch(tester);
    await action(tester, 'export-backup');
    expect(find.text('Backup saved successfully.'), findsNothing);
  });
  workflow('success waits for provider write completion and shows loading', (
    tester,
  ) async {
    pendingExport = Completer<bool>();
    await launch(tester);
    await tester.ensureVisible(find.byKey(const Key('export-backup')));
    await tester.tap(find.byKey(const Key('export-backup')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Backup saved successfully.'), findsNothing);
    pendingExport!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Backup saved successfully.'), findsOneWidget);
  });
  workflow('export provider error displays failure', (tester) async {
    fileError = true;
    await launch(tester);
    await action(tester, 'export-backup');
    expect(find.text('Provider access denied'), findsOneWidget);
    expect(find.text('Backup saved successfully.'), findsNothing);
  });
  workflow('picker cancellation preserves complete state and disk', (
    tester,
  ) async {
    h.controller.increment();
    await tester.pump();
    await h.controller.flush();
    final before = h.store.value;
    await launch(tester);
    await action(tester, 'import-backup');
    expect(h.controller.count, 1);
    expect(h.store.value, before);
    expect(find.text('Restore backup?'), findsNothing);
  });
  workflow(
    'preview and explicit confirmation required, cancel preserves progress',
    (tester) async {
      selected = backup();
      h.controller.increment();
      await tester.pump();
      await h.controller.flush();
      final before = h.store.value;
      await launch(tester);
      await action(tester, 'import-backup');
      expect(find.text('Restore backup?'), findsOneWidget);
      expect(
        find.textContaining(
          'Restoring this backup will replace your current saved progress and settings.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Streak: 0'), findsOneWidget);
      expect(find.textContaining('Custom Mode: 0 / 100'), findsOneWidget);
      expect(h.controller.count, 1);
      await action(tester, 'import-cancel');
      expect(h.store.value, before);
      expect(h.controller.count, 1);
    },
  );
  workflow('confirmed restore updates UI, disk and all settings immediately', (
    tester,
  ) async {
    h.controller.toggleMode();
    h.controller.increment();
    h.controller.toggleStyle();
    h.controller.setIntensity(75);
    selected = backup();
    await tester.pump();
    await h.controller.resetAll();
    await launch(tester);
    await action(tester, 'import-backup');
    expect(h.controller.isCustom, isFalse);
    await action(tester, 'import-confirm');
    expect(h.controller.isCustom, isTrue);
    expect(h.controller.count, 1);
    expect(h.controller.settings.vibrationIntensity, 75);
    expect(find.text('Backup restored successfully.'), findsOneWidget);
    final (state, settings) = await h.repository.load(h.config, h.now);
    expect(state.customCount, 1);
    expect(settings.vibrationIntensity, 75);
    expect(find.text('Vibration Intensity: 75ms'), findsOneWidget);
  });
  workflow('invalid JSON never opens confirmation or changes progress', (
    tester,
  ) async {
    selected = Uint8List.fromList(utf8.encode('{invalid'));
    h.controller.increment();
    await launch(tester);
    await action(tester, 'import-backup');
    expect(find.text('Restore backup?'), findsNothing);
    expect(
      find.text('Invalid backup JSON or missing required fields.'),
      findsOneWidget,
    );
    expect(h.controller.count, 1);
  });
  workflow('failed restore displays failure and preserves live progress', (
    tester,
  ) async {
    selected = backup();
    h.controller.increment();
    await tester.pump();
    await h.controller.flush();
    await launch(tester);
    await action(tester, 'import-backup');
    h.store.fail = true;
    await action(tester, 'import-confirm');
    expect(find.text('Backup restored successfully.'), findsNothing);
    expect(find.textContaining('Backup operation failed.'), findsOneWidget);
    expect(h.controller.count, 1);
  });
  workflow(
    'timer, broadcast and resume refresh prayer UI without selection interaction',
    (tester) async {
      h.now = DateTime(2026, 11, 2, 5, 59, 59);
      await launch(tester);
      await tester.tapAt(const Offset(2, 250));
      await tester.pumpAndSettle();
      h.now = DateTime(2026, 11, 2, 6);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Not available at this time'), findsOneWidget);
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.controller.count, 0);
      h.now = DateTime(2026, 11, 2, 12);
      device.clockEvents.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Dhuhr · Available now'), findsOneWidget);
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.controller.count, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      h.now = DateTime(2026, 11, 2, 16, 45);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Asr · Available now'), findsOneWidget);
      h.now = DateTime(2026, 11, 3);
      device.clockEvents.add(null);
      await tester.pumpAndSettle();
      expect(h.controller.state.date, '2026-11-03');
      expect(find.text('Not available at this time'), findsOneWidget);
    },
  );
}

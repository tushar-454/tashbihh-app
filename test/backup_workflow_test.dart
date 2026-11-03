import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/backup/cloud_backup_coordinator.dart';

import 'cloud_backup_support.dart';
import 'test_support.dart';

void main() {
  late Harness h;
  late TestDevice device;
  late FakeAuth auth;
  late CloudBackupCoordinator cloud;
  void workflow(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      h = Harness();
      device = TestDevice();
      auth = FakeAuth();
      cloud = CloudBackupCoordinator(controller: h.controller, auth: auth);
      addTearDown(() {
        cloud.dispose();
        h.controller.dispose();
        device.dispose();
      });
      await body(tester);
    });
  }

  Future<void> launch(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      TasbihApp(controller: h.controller, device: device, backup: cloud),
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

  workflow(
    'Settings has exactly one Backup/Restore entry; first connection keeps progress',
    (tester) async {
      h.controller.increment();
      await launch(tester);
      expect(find.text('Export Backup'), findsNothing);
      expect(find.text('Import Backup'), findsNothing);
      expect(find.text('Backup/Restore'), findsOneWidget);
      await action(tester, 'backup-restore');
      expect(auth.choices, 1);
      expect(auth.drives['a']!.uploads, 1);
      expect(h.controller.count, 1);
      expect(
        find.text('Backup successful. Connected to a@example.com.'),
        findsWidgets,
      );
    },
  );

  workflow('connected tap uploads immediately and offers account switching', (
    tester,
  ) async {
    await cloud.connect();
    await launch(tester);
    await action(tester, 'backup-restore');
    expect(auth.drives['a']!.uploads, 2);
    expect(find.text('Switch Google account'), findsOneWidget);
    auth.chosen = FakeAuth.b;
    await tester.tap(find.text('Switch Google account'));
    await tester.pumpAndSettle();
    expect(cloud.account!.id, 'b');
    expect(auth.drives['b']!.uploads, 1);
  });

  workflow(
    'background lifecycle uploads once per close and ignores inactive focus',
    (tester) async {
      await cloud.connect();
      await launch(tester);
      h.controller.increment();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(auth.drives['a']!.uploads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(auth.drives['a']!.uploads, 2);
      final saved = cloud.format
          .validate(auth.drives['a']!.bytes!)
          .state(h.config);
      expect(saved.prayers['fajr']!.counts['subhanallah'], 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.drives['a']!.uploads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(auth.drives['a']!.uploads, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    },
  );

  workflow('removing the screen does not create a close backup', (
    tester,
  ) async {
    await cloud.connect();
    await launch(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(auth.drives['a']!.uploads, 1);
  });

  workflow(
    'existing account backup restores settings and custom count immediately',
    (tester) async {
      h.controller.toggleMode();
      h.controller.increment();
      h.controller.setIntensity(75);
      auth.drives['a']!.bytes = cloud.format.wrap(
        cloud.format.serializer.export(
          h.controller.state,
          h.controller.settings,
          h.now,
        ),
        h.now,
      );
      await h.controller.resetAll();
      await launch(tester);
      await action(tester, 'backup-restore');
      expect(h.controller.isCustom, true);
      expect(h.controller.count, 1);
      expect(find.text('Vibration Intensity: 75ms'), findsOneWidget);
      expect(auth.drives['a']!.uploads, 0);
    },
  );

  workflow(
    'pending network operation shows progress and disables repeated backup and reset taps',
    (tester) async {
      auth.drives['a']!.gate = Completer<void>();
      await launch(tester);
      await tester.ensureVisible(find.byKey(const Key('backup-restore')));
      await tester.tap(find.byKey(const Key('backup-restore')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final backup = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('backup-restore')),
          matching: find.byType(OutlinedButton),
        ),
      );
      final reset = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('reset-all')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(backup.onPressed, isNull);
      expect(reset.onPressed, isNull);
      auth.drives['a']!.gate!.complete();
      await tester.pumpAndSettle();
      expect(auth.drives['a']!.uploads, 1);
    },
  );

  workflow(
    'Reset cancellation has exactly two actions and changes no local or cloud data',
    (tester) async {
      h.controller.increment();
      await cloud.connect();
      await launch(tester);
      await action(tester, 'reset-all');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Reset Everything'), findsOneWidget);
      expect(
        find.textContaining(
          'your Google Drive backup for the connected account',
        ),
        findsOneWidget,
      );
      await action(tester, 'reset-cancel');
      expect(h.controller.count, 1);
      expect(auth.drives['a']!.deletions, 0);
    },
  );

  workflow('confirmed Reset Everything clears cloud, counters and connection', (
    tester,
  ) async {
    h.controller.increment();
    await cloud.connect();
    await launch(tester);
    await action(tester, 'reset-all');
    await action(tester, 'reset-confirm');
    expect(h.controller.count, 0);
    expect(auth.drives['a']!.bytes, isNull);
    expect(cloud.account, isNull);
  });

  workflow(
    'cloud deletion failure displays error and preserves local progress',
    (tester) async {
      h.controller.increment();
      await cloud.connect();
      auth.drives['a']!.deleteFailure = true;
      await launch(tester);
      await action(tester, 'reset-all');
      await action(tester, 'reset-confirm');
      expect(h.controller.count, 1);
      expect(auth.drives['a']!.bytes, isNotNull);
      expect(find.text('Deletion failed. Retry.'), findsOneWidget);
    },
  );

  workflow('no connected account reset uses local-only confirmation', (
    tester,
  ) async {
    h.controller.increment();
    await launch(tester);
    await action(tester, 'reset-all');
    expect(
      find.textContaining('local counter progress and settings'),
      findsOneWidget,
    );
    await action(tester, 'reset-confirm');
    expect(h.controller.count, 0);
    expect(auth.resumes, 0);
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

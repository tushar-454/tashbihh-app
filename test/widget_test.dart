import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/models/app_state.dart';

import 'test_support.dart';

void main() {
  late Harness h;
  late TestDevice device;
  tearDown(() {
    h.controller.dispose();
    device.dispose();
  });
  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    // Create asynchronous storage fixtures in the widget test clock zone.
    h = Harness();
    device = TestDevice();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: TasbihApp(controller: h.controller, device: device),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> countTap(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('counter-center')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('main workflow counts, selects Dua and displays completion', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('بِسْمِ اللَّهِ'), findsOneWidget);
    await countTap(tester);
    expect(h.controller.count, 1);
    await tester.tap(find.byKey(const Key('dua-selector')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('dua-ayatulkursi')),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('dua-ayatulkursi')));
    await tester.pumpAndSettle();
    expect(h.controller.count, 0);
    await countTap(tester);
    expect(h.controller.count, 1);
    expect(h.controller.done, isTrue);
    await countTap(tester);
    expect(h.controller.count, 1);
    expect(device.taps, 2);
  });
  testWidgets(
    'Custom Mode settings, style, target, fullscreen and double-tap reset',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const Key('settings-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Vibration Intensity: 40ms'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Custom target: 100'), findsOneWidget);
      await tester.tap(find.byKey(const Key('style-toggle')));
      await tester.pumpAndSettle();
      expect(h.controller.settings.style, CounterStyle.modern);
      await tester.tap(find.byKey(const Key('fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Exit Full Screen'), findsOneWidget);
      final target = find.byKey(const Key('target-slider'));
      await tester.drag(target, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(h.controller.target, greaterThan(100));
      await tester.tapAt(const Offset(10, 250));
      await tester.pumpAndSettle();
      expect(h.controller.count, 0); // dismissal never counts
      await countTap(tester);
      expect(h.controller.count, 1);
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pumpAndSettle();
      expect(h.controller.count, 0);
      await countTap(tester);
      expect(h.controller.count, 1);
    },
  );
  testWidgets(
    'prayer single tap increments once; double tap resets only incomplete Dua',
    (tester) async {
      await launch(tester);
      await countTap(tester);
      expect(h.controller.count, 1);
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 90));
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pumpAndSettle();
      expect(h.controller.count, 0);
      h.controller.selectDua('ayatulkursi');
      await tester.pumpAndSettle();
      await countTap(tester);
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 90));
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pumpAndSettle();
      expect(h.controller.count, 1);
    },
  );
  testWidgets(
    'blocked window, prayer selection restrictions, boundary update and midnight',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const Key('prayer-dhuhr')));
      await tester.pumpAndSettle();
      expect(h.controller.state.selectedPrayer, 'fajr');
      h.now = DateTime(2026, 11, 2, 6);
      h.controller.refresh();
      await tester.pumpAndSettle();
      await countTap(tester);
      expect(h.controller.count, 0);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('prayer-isha'))) +
            const Offset(12, 12),
      );
      await tester.pumpAndSettle();
      expect(h.controller.state.selectedPrayer, 'isha');
      h.now = DateTime(2026, 11, 2, 12);
      h.controller.refresh();
      await tester.pumpAndSettle();
      expect(h.controller.state.selectedPrayer, 'dhuhr');
      await countTap(tester);
      expect(h.controller.count, 1);
      h.now = DateTime(2026, 11, 3);
      h.controller.refresh();
      await tester.pumpAndSettle();
      expect(h.controller.count, 0);
    },
  );
  testWidgets(
    'reset requires confirmation; cancel preserves; Reset Everything restores defaults',
    (tester) async {
      await launch(tester);
      await countTap(tester);
      Future<void> openReset() async {
        await tester.tap(find.byKey(const Key('settings-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reset-all')));
        await tester.pumpAndSettle();
      }

      await openReset();
      expect(find.text('Reset all data?'), findsOneWidget);
      expect(h.controller.count, 1);
      await tester.tap(find.byKey(const Key('reset-cancel')));
      await tester.pumpAndSettle();
      expect(h.controller.count, 1);
      await openReset();
      await tester.tap(find.byKey(const Key('reset-confirm')));
      await tester.pumpAndSettle();
      expect(h.controller.count, 0);
      expect(h.controller.settings.vibrationIntensity, 40);
    },
  );
  testWidgets(
    'outside menu dismissal never increments and escape closes settings',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const Key('dua-selector')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 650));
      await tester.pumpAndSettle();
      expect(h.controller.count, 0);
      await tester.tapAt(const Offset(10, 300));
      await tester.pumpAndSettle();
      expect(h.controller.count, 1);
      await tester.tap(find.byKey(const Key('settings-toggle')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('SETTINGS'), findsNothing);
    },
  );
  for (final size in [
    const Size(280, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'responsive main, dropdown, settings and dialog ${size.width}x${size.height}',
      (tester) async {
        await launch(tester, size: size);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('dua-selector')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(2, 200));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-toggle')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('reset-all')));
        await tester.tap(find.byKey(const Key('reset-all')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('reset-cancel')));
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('200 percent text scale remains scrollable and usable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('settings-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('reset-all')));
    await tester.tap(find.byKey(const Key('reset-all')));
    await tester.pumpAndSettle();
    expect(find.text('Reset all data?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

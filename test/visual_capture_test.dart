import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashbihh/app/app.dart';

import 'test_support.dart';

void main() {
  testWidgets('capture all source UI states with real offline fonts', (
    tester,
  ) async {
    for (final entry in {
      'Comfortaa': ['Comfortaa.ttf'],
      'KohinoorBangla': ['KohinoorBangla.ttf'],
      'Amiri': ['Amiri-Regular.ttf', 'Amiri-Bold.ttf'],
      'Tasbih Emoji': ['TasbihEmoji.ttf'],
      'Tasbih Symbols': ['TasbihSymbols.ttf'],
      'IBM Plex Sans Arabic': [
        'IBMPlexSansArabic-Regular.ttf',
        'IBMPlexSansArabic-Medium.ttf',
        'IBMPlexSansArabic-SemiBold.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await materialIcons.load();
    final h = Harness(date: DateTime(2026, 11, 2, 11));
    final device = TestDevice();
    addTearDown(h.controller.dispose);
    addTearDown(device.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: TasbihApp(controller: h.controller, device: device),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('docs/validation');
        await dir.create(recursive: true);
        await File('${dir.path}/flutter-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('default');
    await tester.tap(find.byKey(const Key('dua-selector')));
    await capture('dua-menu');
    await tester.tapAt(const Offset(2, 300));
    h.now = DateTime(2026, 11, 2, 5);
    h.controller.refresh();
    h.controller.increment();
    h.controller.increment();
    h.controller.increment();
    await capture('classic-partial');
    h.controller.selectDua('ayatulkursi');
    h.controller.increment();
    await capture('completed');
    h.now = DateTime(2026, 11, 2, 7);
    h.controller.refresh();
    h.controller.selectPrayer('dhuhr');
    await capture('blocked-prayer');
    await tester.tap(find.byKey(const Key('settings-toggle')));
    await capture('settings');
    await tester.tap(find.byKey(const Key('mode-toggle')));
    await capture('custom');
    await tester.tap(find.byKey(const Key('style-toggle')));
    await tester.tapAt(const Offset(2, 300));
    for (var i = 0; i < 25; i++) {
      h.controller.increment();
    }
    await capture('modern-partial');
    await tester.tap(find.byKey(const Key('settings-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-all')));
    await capture('reset');
    await tester.tap(find.byKey(const Key('reset-cancel')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(280, 568);
    await capture('narrow');
    tester.view.physicalSize = const Size(1440, 900);
    await capture('large');
    tester.view.physicalSize = const Size(844, 390);
    await capture('landscape');
    await tester.pumpWidget(const SizedBox());
  });
}

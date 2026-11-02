import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/config/tasbih_config.dart';
import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/platform/platform_services.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native prayer, custom, fullscreen, disk restart and confirmed reset workflow',
    (tester) async {
      debugPrint('INTEGRATION: load config');
      final config = await TasbihConfig.load();
      debugPrint('INTEGRATION: load preferences');
      final prefs = await SharedPreferences.getInstance();
      final repository = ProgressRepository(PreferencesStore(prefs));
      var now = DateTime(2026, 11, 2, 5);
      var controller = CounterController(
        config: config,
        repository: repository,
        state: AppState.empty(config, now),
        settings: AppSettings(),
        clock: () => now,
      );
      var device = createDeviceServices();
      debugPrint('INTEGRATION: initialize platform');
      await device.initialize();
      debugPrint('INTEGRATION: platform ready');
      debugPrint('INTEGRATION: mount app');
      await tester.pumpWidget(
        TasbihApp(controller: controller, device: device),
      );
      await tester.pumpAndSettle();
      final capture =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      if (capture) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('android-default');
      }
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(controller.count, 1);
      await tester.tap(find.byKey(const Key('dua-selector')));
      await tester.pumpAndSettle();
      if (capture) await binding.takeScreenshot('android-dua-menu');
      await tester.tap(find.byKey(const Key('dua-alhamdulillah')));
      await tester.pumpAndSettle();
      expect(controller.dua.id, 'alhamdulillah');
      expect(controller.count, 0);
      now = DateTime(2026, 11, 2, 6);
      controller.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.count, 0);
      await tester.tap(find.byKey(const Key('settings-toggle')));
      await tester.pumpAndSettle();
      if (capture) await binding.takeScreenshot('android-settings');
      await tester.tap(find.byKey(const Key('mode-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('style-toggle')));
      await tester.pumpAndSettle();
      expect(controller.isCustom, isTrue);
      expect(controller.settings.style, CounterStyle.modern);
      await tester.tap(find.byKey(const Key('fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(device.fullscreen, isTrue);
      await tester.tap(find.byKey(const Key('fullscreen-toggle')));
      await tester.pumpAndSettle();
      expect(device.fullscreen, isFalse);
      await tester.tapAt(const Offset(2, 260));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(controller.count, 1);
      await controller.flush();
      debugPrint('INTEGRATION: mount app');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      device.dispose();
      // Read the platform store again and build a new controller/widget tree.
      await prefs.reload();
      final (saved, settings) = await repository.load(config, now);
      controller = CounterController(
        config: config,
        repository: repository,
        state: saved,
        settings: settings,
        clock: () => now,
      );
      device = createDeviceServices();
      debugPrint('INTEGRATION: initialize platform');
      await device.initialize();
      debugPrint('INTEGRATION: platform ready');
      debugPrint('INTEGRATION: mount app');
      await tester.pumpWidget(
        TasbihApp(controller: controller, device: device),
      );
      await tester.pumpAndSettle();
      expect(controller.isCustom, isTrue);
      expect(controller.count, 1);
      expect(controller.settings.style, CounterStyle.modern);
      if (capture) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        await binding.takeScreenshot('android-custom-restored');
      }
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('counter-center')));
      await tester.pumpAndSettle();
      expect(controller.count, 0);
      await tester.tap(find.byKey(const Key('settings-toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reset-all')));
      await tester.tap(find.byKey(const Key('reset-all')));
      await tester.pumpAndSettle();
      if (capture) await binding.takeScreenshot('android-reset-confirmation');
      await tester.tap(find.byKey(const Key('reset-cancel')));
      await tester.pumpAndSettle();
      expect(controller.isCustom, isTrue);
      await tester.tap(find.byKey(const Key('settings-toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reset-all')));
      await tester.tap(find.byKey(const Key('reset-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset-confirm')));
      await tester.pumpAndSettle();
      await controller.flush();
      expect(controller.isCustom, isFalse);
      expect(controller.count, 0);
      expect(controller.state.streak, 0);
      debugPrint('INTEGRATION: mount app');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      device.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

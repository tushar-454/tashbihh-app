import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/config/tasbih_config.dart';
import 'core/platform/platform_services.dart';
import 'core/storage/progress_repository.dart';
import 'features/counter/counter_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['amiri', 'ibmplexsansarabic', 'roboto']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  LicenseRegistry.addLicense(() async* {
    for (final family in ['emoji', 'symbols']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-LICENSE.txt'));
    }
  });
  final config = await TasbihConfig.load();
  final repository = ProgressRepository(
    PreferencesStore(await SharedPreferences.getInstance()),
  );
  final (state, settings) = await repository.load(config, DateTime.now());
  final device = createDeviceServices();
  await device.initialize();
  final controller = CounterController(
    config: config,
    repository: repository,
    state: state,
    settings: settings,
  );
  runApp(TasbihApp(controller: controller, device: device));
}

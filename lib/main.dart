import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/backup/cloud_backup_coordinator.dart';
import 'core/backup/google_drive_backup.dart';
import 'core/config/tasbih_config.dart';
import 'core/platform/platform_services.dart';
import 'core/storage/progress_repository.dart';
import 'core/notifications/prayer_notifications.dart';
import 'core/prayer/aladhan_client.dart';
import 'core/prayer/prayer_location.dart';
import 'core/prayer/prayer_time_sync.dart';
import 'core/prayer/prayer_times_repository.dart';
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
  final preferences = await SharedPreferences.getInstance();
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final repository = ProgressRepository(
    android ? AndroidProgressStore() : PreferencesStore(preferences),
  );
  PrayerTimeSync? prayerTimes;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    prayerTimes = PrayerTimeSync(
      config: config,
      repository: PrayerTimesRepository(
        PreferencesStore(
          preferences,
          storageKey: PrayerTimesRepository.cacheKey,
        ),
      ),
      location: PrayerLocation(
        AndroidPrayerLocation(),
        PreferencesStore(
          preferences,
          storageKey: PrayerTimesRepository.permissionKey,
        ),
      ),
      api: AladhanClient(),
      readTimeZone: AndroidPrayerLocation.timeZoneId,
    );
    await prayerTimes.load();
  }
  final (state, settings) = await repository.load(config, DateTime.now());
  final device = createDeviceServices();
  await device.initialize();
  final controller = CounterController(
    config: config,
    repository: repository,
    state: state,
    settings: settings,
    prayerTimes: prayerTimes,
  );
  final backup = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? CloudBackupCoordinator(controller: controller, auth: GoogleBackupAuth())
      : null;
  runApp(
    TasbihApp(
      controller: controller,
      device: device,
      backup: backup,
      notifications: android ? PrayerNotifications() : null,
    ),
  );
}

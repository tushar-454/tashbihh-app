import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/localization/app_localizations.dart';

import '../core/backup/cloud_backup_coordinator.dart';
import '../core/notifications/prayer_notifications.dart';

import '../core/platform/device_services.dart';
import '../features/counter/counter_controller.dart';
import '../features/counter/counter_screen.dart';
import 'theme/tasbih_theme.dart';

class TasbihApp extends StatefulWidget {
  const TasbihApp({
    super.key,
    required this.controller,
    required this.device,
    this.backup,
    this.notifications,
  });
  final CounterController controller;
  final DeviceServices device;
  final CloudBackupCoordinator? backup;
  final PrayerNotifications? notifications;
  @override
  State<TasbihApp> createState() => _TasbihAppState();
}

class _TasbihAppState extends State<TasbihApp> {
  late String _language;
  @override
  void initState() {
    super.initState();
    _language = widget.controller.settings.language;
    widget.controller.addListener(_languageChanged);
  }

  void _languageChanged() {
    final language = widget.controller.settings.language;
    if (_language != language) setState(() => _language = language);
  }

  @override
  void didUpdateWidget(TasbihApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_languageChanged);
      _language = widget.controller.settings.language;
      widget.controller.addListener(_languageChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_languageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: Locale(_language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    onGenerateTitle: (context) => context.tr('app_title'),
    debugShowCheckedModeBanner: false,
    theme: TasbihTheme.forLanguage(_language),
    themeAnimationDuration: Duration.zero,
    home: CounterScreen(
      controller: widget.controller,
      device: widget.device,
      backup: widget.backup,
      notifications: widget.notifications,
    ),
  );
}

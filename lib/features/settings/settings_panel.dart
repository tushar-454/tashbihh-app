import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';

import '../../app/theme/tasbih_theme.dart';
import '../../core/models/app_state.dart';
import '../../core/notifications/prayer_notifications.dart';
import '../../core/platform/device_services.dart';
import '../counter/counter_controller.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.controller,
    required this.device,
    required this.onReset,
    required this.onBackup,
    this.backupStatus,
    this.backupBusy = false,
    this.backupLoading = false,
    this.notifications,
  });
  final CounterController controller;
  final DeviceServices device;
  final VoidCallback onReset, onBackup;
  final String? backupStatus;
  final bool backupBusy, backupLoading;
  final PrayerNotifications? notifications;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Semantics(
      namesRoute: true,
      label: context.tr('settings'),
      child: Container(
        width: 245,
        padding: const EdgeInsets.all(14.4),
        decoration: BoxDecoration(
          color: hsl(220, 15, 14, .96),
          border: Border.all(color: TasbihTheme.border),
          borderRadius: BorderRadius.circular(12.8),
          boxShadow: [
            BoxShadow(
              color: hsl(220, 60, 2, .45),
              blurRadius: 34,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('settings_heading'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: TasbihTheme.gold,
                        fontSize: 10.88,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: context.tr('language'),
                    child: LanguageBadges(controller: c),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(
                      context.tr('vibration', {
                        'value': c.settings.vibrationIntensity,
                      }),
                    ),
                    Slider(
                      key: const Key('vibration-slider'),
                      label: context.tr('milliseconds', {
                        'value': c.settings.vibrationIntensity,
                      }),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      value: c.settings.vibrationIntensity.toDouble(),
                      onChanged: (v) {
                        c.setIntensity(v.round());
                        if (v == 0) device.cancelFeedback();
                      },
                    ),
                  ],
                ),
              ),
              _group(
                context.tr('app_mode'),
                SettingsAction(
                  key: const Key('mode-toggle'),
                  label: c.isCustom
                      ? context.tr('prayer_mode')
                      : context.tr('custom_mode'),
                  onPressed: c.toggleMode,
                ),
              ),
              if (c.isCustom)
                _group(
                  context.tr('custom_target', {'target': c.state.customTarget}),
                  Slider(
                    key: const Key('target-slider'),
                    label: '${c.state.customTarget}',
                    min: 10,
                    max: 1000,
                    divisions: 99,
                    value: c.state.customTarget.clamp(10, 1000).toDouble(),
                    onChanged: (v) => c.setCustomTarget(v.round()),
                  ),
                ),
              _group(
                context.tr('counter_style'),
                SettingsAction(
                  key: const Key('style-toggle'),
                  label: c.settings.style == CounterStyle.classic
                      ? context.tr('modern')
                      : context.tr('classic'),
                  onPressed: c.toggleStyle,
                ),
              ),
              _group(
                context.tr('screen'),
                SettingsAction(
                  key: const Key('fullscreen-toggle'),
                  label: device.fullscreen
                      ? context.tr('exit_fullscreen')
                      : context.tr('fullscreen'),
                  onPressed: device.toggleFullscreen,
                ),
              ),
              _group(
                context.tr('prayer_notifications'),
                _notificationControls(context),
              ),
              _group(
                context.tr('backup_restore_heading'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsAction(
                      key: const Key('backup-restore'),
                      label: context.tr('backup_restore'),
                      onPressed: backupBusy ? null : onBackup,
                    ),
                    const SizedBox(height: 5.6),
                    _label(backupStatus ?? context.tr('connect_drive')),
                    if (backupLoading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 13.6),
              SettingsAction(
                key: const Key('reset-all'),
                label: context.tr('reset_all'),
                danger: true,
                onPressed: backupBusy ? null : onReset,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationControls(BuildContext context) {
    final n = notifications;
    if (n == null) return _label(context.tr('android_only'));
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: context.tr('prayer_notifications'),
            child: Switch.adaptive(
              key: const Key('prayer-notifications-toggle'),
              value: n.enabled,
              onChanged: n.busy ? null : (value) => n.setEnabled(value),
            ),
          ),
          _label(context.l10n.message(n.statusMessage)),
          if (n.enabled && !n.allowed)
            SettingsAction(
              label: context.tr('android_notification_settings'),
              onPressed: () => n.openSettings(),
            ),
          if (n.enabled && n.allowed && !n.exact)
            SettingsAction(
              label: context.tr('precise_reminders'),
              onPressed: () => n.openSettings(alarms: true),
            ),
        ],
      ),
    );
  }

  Widget _label(String value) =>
      Text(value, style: TextStyle(color: TasbihTheme.muted, fontSize: 10.4));
  Widget _group(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 13.6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_label(label), const SizedBox(height: 5.6), child],
    ),
  );
}

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: danger ? TasbihTheme.danger : TasbihTheme.foreground,
      backgroundColor: danger
          ? TasbihTheme.danger.withValues(alpha: .12)
          : hsl(220, 15, 19, .8),
      side: BorderSide(
        color: danger
            ? TasbihTheme.danger.withValues(alpha: .45)
            : TasbihTheme.border,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9.6)),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(vertical: 7.68, horizontal: 8.8),
      textStyle: TextStyle(
        fontFamily: context.l10n.fontFamily,
        fontFamilyFallback: TasbihTheme.fallbackFonts,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w500,
      ),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );
}

class LanguageBadges extends StatelessWidget {
  const LanguageBadges({super.key, required this.controller});
  final CounterController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (final language in ['en', 'bn'])
        Semantics(
          key: Key('language-$language'),
          button: true,
          enabled: !controller.dataLocked,
          onTap: controller.dataLocked
              ? null
              : () => controller.setLanguage(language),
          selected: controller.settings.language == language,
          label: context.tr('language_$language'),
          excludeSemantics: true,
          child: OutlinedButton(
            onPressed: controller.dataLocked
                ? null
                : () => controller.setLanguage(language),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const StadiumBorder(),
              foregroundColor: controller.settings.language == language
                  ? TasbihTheme.gold
                  : TasbihTheme.muted,
              backgroundColor: controller.settings.language == language
                  ? TasbihTheme.gold.withValues(alpha: .14)
                  : TasbihTheme.soft,
              side: BorderSide(
                color: controller.settings.language == language
                    ? TasbihTheme.gold
                    : TasbihTheme.border,
              ),
              textStyle: TextStyle(
                fontFamily: context.l10n.fontFamily,
                fontFamilyFallback: TasbihTheme.fallbackFonts,
                fontSize: 12,
              ),
            ),
            child: Text(context.tr('badge_$language')),
          ),
        ),
    ],
  );
}

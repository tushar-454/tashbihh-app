import 'package:flutter/material.dart';

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
      label: 'Settings',
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
              Text(
                'SETTINGS',
                style: TextStyle(
                  color: TasbihTheme.gold,
                  fontSize: 10.88,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(
                      'Vibration Intensity: ${c.settings.vibrationIntensity}ms',
                    ),
                    Slider(
                      key: const Key('vibration-slider'),
                      label: '${c.settings.vibrationIntensity}ms',
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
                'App mode',
                SettingsAction(
                  key: const Key('mode-toggle'),
                  label: c.isCustom ? 'Prayer Mode' : 'Custom Mode',
                  onPressed: c.toggleMode,
                ),
              ),
              if (c.isCustom)
                _group(
                  'Custom target: ${c.state.customTarget}',
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
                'Counter style',
                SettingsAction(
                  key: const Key('style-toggle'),
                  label: c.settings.style == CounterStyle.classic
                      ? 'Modern'
                      : 'Classic',
                  onPressed: c.toggleStyle,
                ),
              ),
              _group(
                'Screen',
                SettingsAction(
                  key: const Key('fullscreen-toggle'),
                  label: device.fullscreen ? 'Exit Full Screen' : 'Full Screen',
                  onPressed: device.toggleFullscreen,
                ),
              ),
              _group('Prayer Notifications', _notificationControls()),
              _group(
                'Backup & Restore',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsAction(
                      key: const Key('backup-restore'),
                      label: 'Backup/Restore',
                      onPressed: backupBusy ? null : onBackup,
                    ),
                    const SizedBox(height: 5.6),
                    _label(
                      backupStatus ?? 'Connect Google Drive to back up or restore progress.',
                    ),
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
                label: 'Reset all data',
                danger: true,
                onPressed: backupBusy ? null : onReset,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notificationControls() {
    final n = notifications;
    if (n == null) return _label('Available in the Android app.');
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Prayer Notifications',
            child: Switch.adaptive(
              key: const Key('prayer-notifications-toggle'),
              value: n.enabled,
              onChanged: n.busy ? null : (value) => n.setEnabled(value),
            ),
          ),
          _label(n.status),
          if (n.enabled && !n.allowed)
            SettingsAction(
              label: 'Android notification settings',
              onPressed: () => n.openSettings(),
            ),
          if (n.enabled && n.allowed && !n.exact)
            SettingsAction(
              label: 'Allow precise reminders (optional)',
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
      textStyle: const TextStyle(
        fontFamily: 'IBM Plex Sans Arabic',
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w500,
      ),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );
}

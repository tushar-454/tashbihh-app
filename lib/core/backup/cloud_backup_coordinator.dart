import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/counter/counter_controller.dart';
import 'backup_service.dart';
import '../localization/app_localizations.dart';
import 'cloud_backup_format.dart';
import 'cloud_ports.dart';

class CloudBackupCoordinator extends ChangeNotifier {
  CloudBackupCoordinator({required this.controller, required this.auth})
    : format = CloudBackupFormat(BackupSerializer(controller.config)) {
    controller.addListener(_controllerChanged);
  }

  final CounterController controller;
  final BackupAuth auth;
  final CloudBackupFormat format;
  bool busy = false;
  bool _disposed = false;
  bool _foreground = false;
  bool _automaticBackup = false;
  String? _failedDailyReset;
  int? _failedCloseBackup;
  String? _failedStreakEarned;
  AppMessage? statusMessage;
  String? get message => statusMessage?.english;
  Map<String, dynamic> get _metadata => controller.repository.cloudMetadata;
  CloudAccount? get account {
    final id = _metadata['accountId'], email = _metadata['email'];
    return id is String && email is String ? CloudAccount(id, email) : null;
  }

  bool get resetPending => _metadata['resetPending'] == true;
  String? get _pendingDailyReset => _metadata['dailyResetPending'] as String?;
  int? get _pendingCloseBackup => _metadata['closeBackupPending'] as int?;
  String? get _pendingStreakEarned =>
      _metadata['streakEarnedPending'] as String?;
  DateTime? get lastSuccessfulBackup =>
      DateTime.tryParse(_metadata['lastBackup'] as String? ?? '');

  void _status(AppMessage value) {
    statusMessage = value;
    if (!_disposed) notifyListeners();
  }

  /// Fail fast instead of queuing stale taps behind account changes or resets.
  Future<void> _exclusive(
    Future<void> Function() operation, {
    bool lockData = false,
  }) async {
    if (busy || _disposed) {
      if (!_disposed) {
        _status(const AppMessage('cloud_busy'));
      }
      throw const BackupException.localized('cloud_busy');
    }
    busy = true;
    controller.cloudLocked = lockData;
    notifyListeners();
    try {
      await operation();
      _failedDailyReset = null;
      _failedCloseBackup = null;
      _failedStreakEarned = null;
    } catch (error) {
      // Retry failed events on resume, another close, or an explicit tap. No
      // periodic timer or listener notification should repeatedly retry them.
      _failedDailyReset = _pendingDailyReset;
      _failedCloseBackup = _pendingCloseBackup;
      _failedStreakEarned = _pendingStreakEarned;
      _status(
        error is BackupException
            ? error.localizedMessage
            : const AppMessage('cloud_failed'),
      );
      rethrow;
    } finally {
      controller.cloudLocked = false;
      controller.refresh(autoSelect: false);
      busy = false;
      if (!_disposed) notifyListeners();
      _controllerChanged();
    }
  }

  List<int> _payload() {
    controller.refresh(autoSelect: false);
    final payload = format.serializer.export(
      controller.state,
      controller.settings,
      controller.clock(),
    );
    if (payload.length > BackupSerializer.maxBytes) {
      throw const BackupException.localized('backup_too_large_local');
    }
    return payload;
  }

  Map<String, dynamic> _connected(
    CloudAccount account, {
    bool uploaded = false,
  }) => {
    'accountId': account.id,
    'email': account.email,
    if (uploaded) 'lastBackup': controller.clock().toUtc().toIso8601String(),
  };

  Future<void> connect() => _exclusive(() async {
    if (resetPending) {
      throw const BackupException.localized('finish_reset');
    }
    _status(const AppMessage('choose_account'));
    final session = await auth.choose();
    try {
      _status(AppMessage('checking_account', {'email': session.account.email}));
      final bytes = await session.drive.download();
      if (bytes != null) {
        _status(const AppMessage('restoring_cloud'));
        final candidate = format.validate(bytes);
        await controller.commitCloud(
          backup: candidate,
          metadata: _connected(session.account),
        );
        _status(
          AppMessage('restore_connected', {'email': session.account.email}),
        );
      } else {
        _status(const AppMessage('creating_backup'));
        final payload = _payload();
        await session.drive.upload(
          format.wrap(payload, controller.clock()),
          onlyIfMissing: true,
        );
        await controller.commitCloud(
          metadata: _connected(session.account, uploaded: true),
        );
        _status(
          AppMessage('backup_connected', {'email': session.account.email}),
        );
      }
    } finally {
      session.drive.close();
    }
  }, lockData: true);

  Future<void> backupNow() => _exclusive(() => _backup(interactive: true));

  Future<void> _backup({required bool interactive}) async {
    final selected = account;
    if (selected == null || resetPending) {
      throw const BackupException.localized('connect_first');
    }
    // Capture data and event revisions together before network awaits. A close
    // or streak change during this upload requires a fresh follow-up snapshot.
    final payload = _payload();
    final dailyReset = _pendingDailyReset;
    final closeBackup = _pendingCloseBackup;
    final streakEarned = _pendingStreakEarned;
    _status(const AppMessage('backing_up'));
    final session = await auth.resume(selected, interactive: interactive);
    try {
      _verifyAccount(selected, session);
      await session.drive.upload(format.wrap(payload, controller.clock()));
      await controller.saveCloudMetadata(
        {
          ..._metadata,
          'lastBackup': controller.clock().toUtc().toIso8601String(),
        },
        uploadedDailyReset: dailyReset,
        uploadedCloseBackup: closeBackup,
        uploadedStreakEarned: streakEarned,
      );
      _status(const AppMessage('backup_success'));
    } finally {
      session.drive.close();
    }
  }

  void _verifyAccount(CloudAccount selected, CloudSession session) {
    if (selected.id != session.account.id) {
      throw const BackupException.localized('account_changed');
    }
  }

  Future<void> resetEverything() => _exclusive(() async {
    final selected = account;
    if (selected != null) {
      // Durable intent survives termination after cloud deletion. Startup never
      // uploads or restores until the user explicitly retries this reset.
      await controller.commitCloud(
        metadata: {..._metadata, 'resetPending': true},
      );
      _status(const AppMessage('deleting_backup'));
      final session = await auth.resume(selected, interactive: true);
      try {
        _verifyAccount(selected, session);
        await session.drive.deleteAndVerify();
      } finally {
        session.drive.close();
      }
    }
    await controller.commitCloud(reset: true, metadata: {});
    _status(const AppMessage('reset_disconnected'));
  }, lockData: true);

  Future<void> retryPending() {
    _failedDailyReset = null;
    _failedCloseBackup = null;
    _failedStreakEarned = null;
    return _backupPending();
  }

  bool get _hasPendingBackup =>
      (_pendingCloseBackup != null &&
          _pendingCloseBackup != _failedCloseBackup) ||
      (_foreground &&
          ((_pendingDailyReset != null &&
                  _pendingDailyReset != _failedDailyReset) ||
              (_pendingStreakEarned != null &&
                  _pendingStreakEarned != _failedStreakEarned)));

  Future<void> _backupPending() async {
    if (_disposed ||
        busy ||
        _automaticBackup ||
        account == null ||
        resetPending) {
      return;
    }
    _automaticBackup = true;
    try {
      controller.refresh(autoSelect: false);
      if (_hasPendingBackup) {
        await _exclusive(() => _backup(interactive: false));
      }
    } catch (_) {
      // The durable event markers survive failure and process termination.
    } finally {
      _automaticBackup = false;
    }
    _controllerChanged();
  }

  void _controllerChanged() {
    if (!_disposed && !busy && !_automaticBackup && _hasPendingBackup) {
      unawaited(_backupPending());
    }
  }

  void resume() {
    _foreground = true;
    // Caller deliberately does not block counter startup on the network.
    unawaited(retryPending());
    if (resetPending) {
      _status(const AppMessage('reset_interrupted'));
    }
  }

  void suspend({bool backupOnClose = true}) {
    final wasForeground = _foreground;
    _foreground = false;
    if (_disposed ||
        !wasForeground ||
        !backupOnClose ||
        controller.dataLocked) {
      return;
    }
    controller.requestCloseBackup();
    _controllerChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_controllerChanged);
    super.dispose();
  }
}

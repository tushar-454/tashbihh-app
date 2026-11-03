import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/counter/counter_controller.dart';
import 'backup_service.dart';
import 'cloud_backup_format.dart';
import 'cloud_ports.dart';

class CloudBackupCoordinator extends ChangeNotifier {
  CloudBackupCoordinator({
    required this.controller,
    required this.auth,
    required this.scheduler,
  }) : format = CloudBackupFormat(BackupSerializer(controller.config));

  final CounterController controller;
  final BackupAuth auth;
  final BackupScheduler scheduler;
  final CloudBackupFormat format;
  static const interval = Duration(hours: 12);
  bool busy = false;
  bool _disposed = false;
  bool _foreground = false;
  DateTime? _retryAfter;
  String? message;
  Map<String, dynamic> get _metadata => controller.repository.cloudMetadata;
  CloudAccount? get account {
    final id = _metadata['accountId'], email = _metadata['email'];
    return id is String && email is String ? CloudAccount(id, email) : null;
  }

  bool get resetPending => _metadata['resetPending'] == true;
  DateTime? get lastSuccessfulBackup =>
      DateTime.tryParse(_metadata['lastBackup'] as String? ?? '');

  void _status(String value) {
    message = value;
    if (!_disposed) notifyListeners();
  }

  /// Fail fast instead of queuing stale taps behind account changes or resets.
  Future<void> _exclusive(
    Future<void> Function() operation, {
    bool lockData = false,
  }) async {
    if (busy || _disposed) {
      if (!_disposed) {
        _status('Another cloud operation is in progress. Please retry.');
      }
      throw const BackupException(
        'Another cloud operation is in progress. Please retry.',
      );
    }
    busy = true;
    controller.cloudLocked = lockData;
    notifyListeners();
    try {
      await operation();
      _retryAfter = null;
    } catch (error) {
      _status(
        error is BackupException ? error.message : 'Cloud operation failed. Local progress remains active. Check your connection and free device storage before retrying.',
      );
      rethrow;
    } finally {
      busy = false;
      controller.cloudLocked = false;
      controller.refresh(autoSelect: false);
      if (!_disposed) notifyListeners();
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
      throw const BackupException(
        'Backup is too large. Local progress was kept.',
      );
    }
    return payload;
  }

  String _fingerprint() => format.digest(
    utf8.encode(
      jsonEncode({
        'state': controller.state.toJson(),
        'settings': controller.settings.toJson(),
      }),
    ),
  );

  Map<String, dynamic> _connected(
    CloudAccount account, {
    bool uploaded = false,
  }) => {
    'accountId': account.id,
    'email': account.email,
    'lastCheck': controller.clock().toUtc().toIso8601String(),
    if (uploaded) 'lastBackup': controller.clock().toUtc().toIso8601String(),
    // A restore may normalize dated progress, so its first scheduled backup
    // should upload the normalized state rather than skipping it.
    if (uploaded) 'fingerprint': _fingerprint(),
  };

  Future<void> connect() => _exclusive(() async {
    if (resetPending) {
      throw const BackupException(
        'Finish Reset Everything before connecting an account.',
      );
    }
    _status('Choose a Google account and allow private Drive backup access.');
    final session = await auth.choose();
    try {
      _status('Checking ${session.account.email} for a cloud backup…');
      final bytes = await session.drive.download();
      if (bytes != null) {
        _status('Restoring cloud data…');
        final candidate = format.validate(bytes);
        await controller.commitCloud(
          backup: candidate,
          metadata: _connected(session.account),
        );
        _status('Restore successful. Connected to ${session.account.email}.');
      } else {
        _status('Creating first cloud backup…');
        final payload = _payload();
        await session.drive.upload(
          format.wrap(payload, controller.clock()),
          onlyIfMissing: true,
        );
        await controller.commitCloud(
          metadata: _connected(session.account, uploaded: true),
        );
        _status('Backup successful. Connected to ${session.account.email}.');
      }
    } finally {
      session.drive.close();
    }
  }, lockData: true);

  Future<void> backupNow() => _exclusive(() => _backup(interactive: true));

  Future<void> _backup({required bool interactive}) async {
    final selected = account;
    if (selected == null || resetPending) {
      throw const BackupException(
        'Connect Backup/Restore first, or finish the pending reset.',
      );
    }
    // Capture before network awaits. Later counts remain eligible for the next
    // upload; synchronization metadata records this captured fingerprint only.
    final payload = _payload();
    final fingerprint = _fingerprint();
    _status('Backing up current progress…');
    final session = await auth.resume(selected, interactive: interactive);
    try {
      _verifyAccount(selected, session);
      await session.drive.upload(format.wrap(payload, controller.clock()));
      await controller.saveCloudMetadata({
        ..._metadata,
        'lastBackup': controller.clock().toUtc().toIso8601String(),
        'lastCheck': controller.clock().toUtc().toIso8601String(),
        'fingerprint': fingerprint,
      });
      _status('Backup successful.');
    } finally {
      session.drive.close();
    }
  }

  void _verifyAccount(CloudAccount selected, CloudSession session) {
    if (selected.id != session.account.id) {
      throw const BackupException(
        'Account changed. Use Switch Google account before syncing.',
      );
    }
  }

  Future<void> resetEverything() => _exclusive(() async {
    scheduler.stop();
    final selected = account;
    if (selected != null) {
      // Durable intent survives termination after cloud deletion. Startup never
      // uploads or restores until the user explicitly retries this reset.
      await controller.commitCloud(
        metadata: {..._metadata, 'resetPending': true},
      );
      _status('Deleting the connected account’s Google Drive backup…');
      final session = await auth.resume(selected, interactive: true);
      try {
        _verifyAccount(selected, session);
        await session.drive.deleteAndVerify();
      } finally {
        session.drive.close();
      }
    }
    await controller.commitCloud(reset: true, metadata: {});
    _status(
      'Everything reset. Connect Backup/Restore to set up backups again.',
    );
  }, lockData: true);

  Future<void> checkDue() async {
    if (_disposed || busy || account == null || resetPending) return;
    final now = controller.clock();
    if (_retryAfter != null && now.isBefore(_retryAfter!)) return;
    final checked = DateTime.tryParse(_metadata['lastCheck'] as String? ?? '');
    if (checked != null && now.difference(checked) < interval) return;
    try {
      await _exclusive(() async {
        controller.refresh(autoSelect: false);
        if (_metadata['fingerprint'] == _fingerprint()) {
          await controller.saveCloudMetadata({
            ..._metadata,
            'lastCheck': now.toUtc().toIso8601String(),
          });
          return;
        }
        await _backup(interactive: false);
      });
    } catch (_) {
      _retryAfter = now.add(const Duration(minutes: 5));
    }
  }

  void resume() {
    _foreground = true;
    scheduler.start(checkDue);
    // Caller deliberately does not block counter startup on the network.
    checkDue();
    if (resetPending) {
      _status(
        'Reset was interrupted. Retry Reset Everything to finish safely.',
      );
    }
  }

  void suspend() {
    _foreground = false;
    scheduler.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_foreground) scheduler.stop();
    super.dispose();
  }
}

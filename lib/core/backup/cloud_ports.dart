import 'dart:async';

class CloudAccount {
  const CloudAccount(this.id, this.email);
  final String id, email;
}

class CloudSession {
  const CloudSession(this.account, this.drive);
  final CloudAccount account;
  final BackupDrive drive;
}

abstract interface class BackupAuth {
  Future<CloudSession> choose();
  Future<CloudSession> resume(
    CloudAccount account, {
    required bool interactive,
  });
}

abstract interface class BackupDrive {
  Future<List<int>?> download();
  Future<void> upload(List<int> bytes, {bool onlyIfMissing = false});

  /// Must verify absence, including when the file was already missing.
  Future<void> deleteAndVerify();
  void close();
}

abstract interface class BackupScheduler {
  void start(Future<void> Function() check);
  void stop();
}

/// Foreground fallback: Android Sign-In requires an Activity for account/session
/// recovery. No bearer tokens are persisted for a headless worker.
class ForegroundBackupScheduler implements BackupScheduler {
  Timer? _timer;
  @override
  void start(Future<void> Function() check) {
    stop();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(check()),
    );
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

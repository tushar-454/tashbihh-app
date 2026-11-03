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

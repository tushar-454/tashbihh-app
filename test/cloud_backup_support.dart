import 'dart:async';

import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/backup/cloud_ports.dart';

class FakeDrive implements BackupDrive {
  List<int>? bytes;
  int downloads = 0, uploads = 0, deletions = 0;
  bool offline = false, deleteFailure = false;
  Completer<void>? gate;
  void Function()? onDeleted;
  Future<void> check() async {
    await gate?.future;
    if (offline) throw const BackupException('Network unavailable. Retry.');
  }

  @override
  Future<List<int>?> download() async {
    downloads++;
    await check();
    return bytes;
  }

  @override
  Future<void> upload(List<int> value, {bool onlyIfMissing = false}) async {
    await check();
    if (onlyIfMissing && bytes != null) throw StateError('Existing backup');
    uploads++;
    bytes = List.of(value);
  }

  @override
  Future<void> deleteAndVerify() async {
    await check();
    if (deleteFailure) throw const BackupException('Deletion failed. Retry.');
    deletions++;
    bytes = null;
    onDeleted?.call();
  }

  @override
  void close() {}
}

class FakeAuth implements BackupAuth {
  static const a = CloudAccount('a', 'a@example.com');
  static const b = CloudAccount('b', 'b@example.com');
  CloudAccount chosen = a;
  CloudAccount? wrongResume;
  bool denied = false;
  int choices = 0, resumes = 0;
  final drives = {'a': FakeDrive(), 'b': FakeDrive()};

  @override
  Future<CloudSession> choose() async {
    choices++;
    if (denied) throw const BackupException('Authentication denied.');
    return CloudSession(chosen, drives[chosen.id]!);
  }

  @override
  Future<CloudSession> resume(
    CloudAccount account, {
    required bool interactive,
  }) async {
    resumes++;
    if (denied) throw const BackupException('Authentication expired.');
    final selected = wrongResume ?? account;
    return CloudSession(selected, drives[selected.id]!);
  }
}

class FakeScheduler implements BackupScheduler {
  Future<void> Function()? check;
  int starts = 0, stops = 0;
  @override
  void start(Future<void> Function() callback) {
    starts++;
    check = callback;
  }

  @override
  void stop() {
    stops++;
    check = null;
  }
}

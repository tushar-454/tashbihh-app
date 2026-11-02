import 'package:flutter/services.dart';

/// Android SAF handles content URIs entirely on the platform side.
class BackupDocuments {
  static const channel = MethodChannel('tasbih/backup_documents');
  Future<bool> save(String filename, Uint8List bytes) async =>
      await channel.invokeMethod<bool>('save', {
        'filename': filename,
        'bytes': bytes,
      }) ??
      false;
  Future<Uint8List?> open() => channel.invokeMethod<Uint8List>('open');
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'backup_service.dart';

/// A checksummed envelope around the existing, strictly validated JSON format.
/// Hashes detect accidental damage, not malicious modification by an account owner.
class CloudBackupFormat {
  CloudBackupFormat(this.serializer);
  final BackupSerializer serializer;
  static const maxBytes = BackupSerializer.maxBytes * 2;

  String digest(List<int> bytes) => sha256.convert(bytes).toString();

  Uint8List wrap(List<int> payload, DateTime now) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'tashbihh_drive_backup',
        'schemaVersion': 1,
        'createdAt': now.toUtc().toIso8601String(),
        'sha256': digest(payload),
        'payload': base64Encode(payload),
      }),
    ),
  );

  ValidatedBackup validate(List<int> bytes) {
    try {
      if (bytes.length > maxBytes) throw const FormatException();
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (root['format'] != 'tashbihh_drive_backup' ||
          root['schemaVersion'] != 1 ||
          root['createdAt'] is! String ||
          !root['createdAt'].endsWith('Z') ||
          DateTime.tryParse(root['createdAt']) == null) {
        throw const FormatException();
      }
      final payload = base64Decode(root['payload'] as String);
      if (digest(payload) != root['sha256']) throw const FormatException();
      return serializer.validate(payload);
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException.localized('backup_corrupt');
    }
  }
}

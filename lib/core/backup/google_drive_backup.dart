import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'backup_service.dart';
import 'cloud_backup_format.dart';
import 'cloud_ports.dart';

class GoogleBackupAuth implements BackupAuth {
  static const serverClientId =
      '617717835916-sb6vsc47a88jvtgvuubredil9vgl2f4u.apps.googleusercontent.com';
  static const scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;
  final Map<String, GoogleSignInAccount> _knownUsers = {};

  Future<void> _initialize() =>
      _initialization ??= _signIn.initialize(serverClientId: serverClientId);

  Future<CloudSession> _authorize(
    GoogleSignInAccount user, {
    required bool interactive,
  }) async {
    var authorization = await user.authorizationClient.authorizationForScopes(
      scopes,
    );
    if (authorization == null && interactive) {
      authorization = await user.authorizationClient.authorizeScopes(scopes);
    }
    if (authorization == null) {
      throw const BackupException(
        'Google authorization expired. Tap Backup/Restore to authorize again.',
      );
    }
    final token = authorization.accessToken;
    return CloudSession(
      CloudAccount(user.id, user.email),
      GoogleBackupDrive(
        client: http.Client(),
        token: token,
        onUnauthorized: () => user.authorizationClient.clearAuthorizationToken(
          accessToken: token,
        ),
      ),
    );
  }

  Future<CloudSession> _guard(Future<CloudSession> Function() action) async {
    try {
      await _initialize();
      return await action();
    } on GoogleSignInException catch (e) {
      throw BackupException(switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Google account selection or permission was cancelled. Local progress was kept.',
        GoogleSignInExceptionCode.clientConfigurationError => 'Google Sign-In configuration error. Check the Android signing certificate and OAuth client.',
        _ => 'Google authentication or permission failed. Check your connection and try Backup/Restore again.',
      });
    }
  }

  @override
  Future<CloudSession> choose() => _guard(() async {
    // Sign-out clears the SDK picker session, not the coordinator's committed
    // identity. Never disconnect/revoke the previous account during a switch.
    await _signIn.signOut();
    final user = await _signIn.authenticate(scopeHint: scopes);
    _knownUsers[user.id] = user;
    return _authorize(user, interactive: true);
  });

  @override
  Future<CloudSession> resume(
    CloudAccount account, {
    required bool interactive,
  }) => _guard(() async {
    var user = _knownUsers[account.id];
    user ??= await _signIn.attemptLightweightAuthentication();
    if ((user == null || user.id != account.id) && interactive) {
      await _signIn.signOut();
      user = await _signIn.authenticate(scopeHint: scopes);
    }
    if (user == null || user.id != account.id) {
      throw const BackupException(
        'Authenticate the connected Google account to continue. Use Switch Google account to change accounts.',
      );
    }
    _knownUsers[user.id] = user;
    return _authorize(user, interactive: interactive);
  });
}

/// Drive REST v3 with the minimum appdata scope. IDs are discovered inside the
/// private folder for each operation, never persisted or reused across accounts.
class GoogleBackupDrive implements BackupDrive {
  GoogleBackupDrive({
    required this.client,
    required this.token,
    this.onUnauthorized,
  });
  final http.Client client;
  final String token;
  final Future<void> Function()? onUnauthorized;
  static const filename = 'tasbihh_backup.json';
  static const timeout = Duration(seconds: 30);

  Future<http.Response> _request(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    bool missingAllowed = false,
  }) async {
    try {
      final request = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $token';
      if (contentType != null) request.headers['Content-Type'] = contentType;
      if (body != null) request.bodyBytes = body;
      final response = await client.send(request).timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > CloudBackupFormat.maxBytes) {
          throw const BackupException(
            'Cloud backup is too large. Local progress was kept.',
          );
        }
        bytes.addAll(chunk);
      }
      final result = http.Response.bytes(bytes, response.statusCode);
      if (result.statusCode == 401) {
        await onUnauthorized?.call();
        throw const BackupException(
          'Google authorization expired. Tap Backup/Restore to authorize again.',
        );
      }
      if (result.statusCode == 403) {
        throw const BackupException(
          'Google Drive permission denied or quota exceeded. Allow private app-data access and retry.',
        );
      }
      if (missingAllowed && result.statusCode == 404) return result;
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw BackupException(
          'Google Drive operation failed (${result.statusCode}). Please retry.',
        );
      }
      return result;
    } on TimeoutException {
      throw const BackupException(
        'Network unavailable or timed out. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const BackupException(
        'Network unavailable. Check your internet connection and retry.',
      );
    }
  }

  Future<List<String>> _files() async {
    final ids = <String>[];
    String? page;
    do {
      final response = await _request(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'spaces': 'appDataFolder',
          'q':
              "name = '$filename' and trashed = false and 'appDataFolder' in parents",
          'fields': 'nextPageToken,incompleteSearch,files(id)',
          'orderBy': 'modifiedTime desc',
          'pageSize': '100',
          'pageToken': ?page,
        }),
      );
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      if (root['incompleteSearch'] == true) {
        throw const BackupException(
          'Drive search was incomplete. Retry before creating or deleting a backup.',
        );
      }
      ids.addAll((root['files'] as List).map((f) => f['id'] as String));
      page = root['nextPageToken'] as String?;
    } while (page != null);
    return ids;
  }

  Uri _file(String id, [Map<String, String>? query]) =>
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', query);

  @override
  Future<List<int>?> download() async {
    final ids = await _files();
    if (ids.isEmpty) return null;
    // A file disappearing after list must fail, never be treated as a new
    // account and silently upload over an unchecked remote state.
    return (await _request(
      'GET',
      _file(ids.first, {'alt': 'media'}),
    )).bodyBytes;
  }

  @override
  Future<void> upload(List<int> bytes, {bool onlyIfMissing = false}) async {
    if (bytes.length > CloudBackupFormat.maxBytes) {
      throw const BackupException('Backup exceeds the cloud size limit.');
    }
    final ids = await _files();
    if (ids.isNotEmpty) {
      if (onlyIfMissing) {
        throw const BackupException(
          'A cloud backup appeared during connection. Retry to restore it safely.',
        );
      }
      await _request(
        'PATCH',
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/${ids.first}', {
          'uploadType': 'media',
        }),
        body: bytes,
        contentType: 'application/json; charset=UTF-8',
      );
    } else {
      const boundary = 'tashbihh_backup_boundary';
      final body = <int>[
        ...utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n',
        ),
        ...utf8.encode(
          jsonEncode({
            'name': filename,
            'parents': ['appDataFolder'],
          }),
        ),
        ...utf8.encode(
          '\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n',
        ),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      await _request(
        'POST',
        Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
          'uploadType': 'multipart',
        }),
        body: body,
        contentType: 'multipart/related; boundary=$boundary',
      );
    }
  }

  @override
  Future<void> deleteAndVerify() async {
    // Include legacy duplicates of this exact app-owned filename; leave all
    // other app data and every other Google account untouched.
    for (final id in await _files()) {
      await _request('DELETE', _file(id), missingAllowed: true);
      final verification = await _request(
        'GET',
        _file(id, {'fields': 'id'}),
        missingAllowed: true,
      );
      if (verification.statusCode != 404) {
        throw const BackupException(
          'Cloud deletion could not be verified. Local progress was kept.',
        );
      }
    }
    if ((await _files()).isNotEmpty) {
      throw const BackupException(
        'Cloud backup still exists. Retry Reset Everything. Local progress was kept.',
      );
    }
  }

  @override
  void close() => client.close();
}

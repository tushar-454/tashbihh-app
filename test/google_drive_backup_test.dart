import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashbihh/core/backup/backup_service.dart';
import 'package:tashbihh/core/backup/cloud_backup_format.dart';
import 'package:tashbihh/core/backup/google_drive_backup.dart';

void main() {
  http.Response listing(List<String> ids, {String? page}) => http.Response(
    jsonEncode({
      'files': ids.map((id) => {'id': id}).toList(),
      'nextPageToken': ?page,
    }),
    200,
  );

  test('download searches exact filename in private appdata only with bearer authorization', () async {
    final requests = <http.Request>[];
    final drive = GoogleBackupDrive(
      token: 'test-token',
      client: MockClient((r) async {
        requests.add(r);
        expect(r.headers['Authorization'], 'Bearer test-token');
        if (r.url.path == '/drive/v3/files') return listing(['own-file']);
        expect(r.url.path, '/drive/v3/files/own-file');
        expect(r.url.queryParameters['alt'], 'media');
        return http.Response('backup bytes', 200);
      }),
    );
    expect(utf8.decode((await drive.download())!), 'backup bytes');
    final query = requests.first.url.queryParameters;
    expect(query['spaces'], 'appDataFolder');
    expect(query['q'], contains("name = 'tasbihh_backup.json'"));
    expect(query['q'], contains("'appDataFolder' in parents"));
    drive.close();
  });

  test('missing backup returns null without creating files', () async {
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        expect(r.method, 'GET');
        return listing([]);
      }),
    );
    expect(await drive.download(), isNull);
    drive.close();
  });

  test('existing backup updated with PATCH and never POST', () async {
    final methods = <String>[];
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        methods.add(r.method);
        if (r.method == 'GET') return listing(['own-file']);
        expect(r.method, 'PATCH');
        expect(r.url.path, '/upload/drive/v3/files/own-file');
        expect(r.url.queryParameters['uploadType'], 'media');
        expect(r.body, 'new bytes');
        return http.Response('{}', 200);
      }),
    );
    await drive.upload(utf8.encode('new bytes'));
    expect(methods, ['GET', 'PATCH']);
    drive.close();
  });

  test('first backup created with multipart appDataFolder metadata', () async {
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        if (r.method == 'GET') return listing([]);
        expect(r.method, 'POST');
        expect(r.url.queryParameters['uploadType'], 'multipart');
        expect(r.headers['Content-Type'], contains('multipart/related'));
        expect(r.body, contains('"parents":["appDataFolder"]'));
        expect(r.body, contains('"name":"tasbihh_backup.json"'));
        expect(r.body, contains('new bytes'));
        return http.Response('{}', 200);
      }),
    );
    await drive.upload(utf8.encode('new bytes'), onlyIfMissing: true);
    drive.close();
  });

  test(
    'new file detected during first connection prevents unchecked overwrite',
    () async {
      final drive = GoogleBackupDrive(
        token: 't',
        client: MockClient((r) async {
          expect(r.method, 'GET');
          return listing(['appeared']);
        }),
      );
      await expectLater(
        drive.upload([1], onlyIfMissing: true),
        throwsA(isA<BackupException>()),
      );
      drive.close();
    },
  );

  test('delete follows pagination, deletes only discovered files and verifies 404 and empty list', () async {
    final deleted = <String>{};
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        if (r.url.path == '/drive/v3/files') {
          expect(r.url.queryParameters['spaces'], 'appDataFolder');
          if (deleted.length == 2) {
            return listing([]);
          }
          return r.url.queryParameters['pageToken'] == null
              ? listing(['own-1'], page: 'next')
              : listing(['own-2']);
        }
        final id = r.url.pathSegments.last;
        expect(['own-1', 'own-2'], contains(id));
        if (r.method == 'DELETE') {
          deleted.add(id);
          return http.Response('', 204);
        }
        return http.Response('', deleted.contains(id) ? 404 : 200);
      }),
    );
    await drive.deleteAndVerify();
    expect(deleted, {'own-1', 'own-2'});
    drive.close();
  });

  test(
    'already missing backup verified with search and needs no deletion',
    () async {
      var searches = 0;
      final drive = GoogleBackupDrive(
        token: 't',
        client: MockClient((r) async {
          searches++;
          expect(r.method, 'GET');
          return listing([]);
        }),
      );
      await drive.deleteAndVerify();
      expect(searches, 2);
      drive.close();
    },
  );

  test('deletion 404 is safe when absence confirmed', () async {
    var searches = 0;
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        if (r.url.path == '/drive/v3/files') {
          return listing(searches++ == 0 ? ['gone'] : []);
        }
        return http.Response('', 404);
      }),
    );
    await drive.deleteAndVerify();
    drive.close();
  });

  test('remote still present after deletion never reports success', () async {
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient((r) async {
        if (r.url.path == '/drive/v3/files') return listing(['own']);
        return http.Response('{}', r.method == 'DELETE' ? 204 : 200);
      }),
    );
    await expectLater(drive.deleteAndVerify(), throwsA(isA<BackupException>()));
    drive.close();
  });

  for (final status in [401, 403, 429, 503]) {
    test(
      'Drive HTTP $status fails without mutation, invalidates expired token only',
      () async {
        var invalidated = false;
        final drive = GoogleBackupDrive(
          token: 't',
          onUnauthorized: () async {
            invalidated = true;
          },
          client: MockClient((r) async => http.Response('{}', status)),
        );
        await expectLater(drive.download(), throwsA(isA<BackupException>()));
        expect(invalidated, status == 401);
        drive.close();
      },
    );
  }

  test('incomplete search cannot be interpreted as no backup', () async {
    final drive = GoogleBackupDrive(
      token: 't',
      client: MockClient(
        (r) async => http.Response('{"files":[],"incompleteSearch":true}', 200),
      ),
    );
    await expectLater(drive.download(), throwsA(isA<BackupException>()));
    drive.close();
  });

  test(
    'disappearing file after search fails instead of initializing account',
    () async {
      final drive = GoogleBackupDrive(
        token: 't',
        client: MockClient((r) async {
          if (r.url.path == '/drive/v3/files') return listing(['vanished']);
          return http.Response('', 404);
        }),
      );
      await expectLater(drive.download(), throwsA(isA<BackupException>()));
      drive.close();
    },
  );

  test(
    'oversized streamed download and network exception preserve failure status',
    () async {
      var huge = true;
      final drive = GoogleBackupDrive(
        token: 't',
        client: MockClient((r) async {
          if (!huge) throw http.ClientException('offline');
          if (r.url.path == '/drive/v3/files') return listing(['own']);
          return http.Response('x' * (CloudBackupFormat.maxBytes + 1), 200);
        }),
      );
      await expectLater(drive.download(), throwsA(isA<BackupException>()));
      huge = false;
      await expectLater(drive.download(), throwsA(isA<BackupException>()));
      drive.close();
    },
  );
}

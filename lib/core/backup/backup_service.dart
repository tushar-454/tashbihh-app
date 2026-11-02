import 'dart:convert';
import 'dart:typed_data';

import '../config/tasbih_config.dart';
import '../models/app_state.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Detached validated data; models are reconstructed at commit, so preview
/// callers cannot mutate either the active controller or the restore candidate.
class ValidatedBackup {
  ValidatedBackup._(this.exportedAt, this.appVersion, this._data);
  final DateTime exportedAt;
  final String appVersion;
  final String _data;
  Map<String, dynamic> get data => jsonDecode(_data) as Map<String, dynamic>;
  AppState state(TasbihConfig config) =>
      AppState.fromJson(config, data['state']);
  AppSettings get settings => AppSettings.fromJson(data['settings']);
}

class BackupSerializer {
  BackupSerializer(this.config);
  final TasbihConfig config;
  static const maxBytes = 1024 * 1024;
  static const format = 'tasbih_backup';
  static const schemaVersion = 1;

  Uint8List export(AppState state, AppSettings settings, DateTime now) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': format,
            'schemaVersion': schemaVersion,
            'exportedAt': now.toUtc().toIso8601String(),
            'appVersion': const String.fromEnvironment(
              'FLUTTER_BUILD_NAME',
              defaultValue: '1.0.0',
            ),
            'data': {'state': state.toJson(), 'settings': settings.toJson()},
          }),
        ),
      );

  ValidatedBackup validate(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const BackupException('Backup is too large. Maximum size is 1 MB.');
    }
    try {
      final root = _map(jsonDecode(utf8.decode(bytes)));
      _require(root['format'] == format, 'This is not a Tasbih backup.');
      _require(
        root['schemaVersion'] is int && root['schemaVersion'] == 1,
        'Unsupported backup version. Use an app that supports this backup.',
      );
      final stamp = root['exportedAt'];
      _require(
        stamp is String &&
            RegExp(
              r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$',
            ).hasMatch(stamp),
        'Backup timestamp must include a timezone.',
      );
      final timestamp = DateTime.parse(stamp as String);
      _date(stamp.substring(0, 10));
      _require(
        timestamp.year >= 1 && timestamp.year <= 9999,
        'Invalid backup timestamp.',
      );
      final time = stamp.substring(11, 19).split(':').map(int.parse).toList();
      _require(
        time[0] < 24 && time[1] < 60 && time[2] < 60,
        'Invalid backup timestamp.',
      );
      if (!stamp.endsWith('Z')) {
        final offset = stamp
            .substring(stamp.length - 5)
            .split(':')
            .map(int.parse)
            .toList();
        _require(
          offset[0] <= 23 && offset[1] < 60,
          'Invalid timestamp offset.',
        );
      }
      _require(
        root['appVersion'] is String &&
            (root['appVersion'] as String).isNotEmpty &&
            (root['appVersion'] as String).length <= 100,
        'Missing app version.',
      );
      final data = _map(root['data']);
      final state = _map(data['state']);
      _daily(state);
      _require(
        config.prayers.any((p) => p.id == state['selectedPrayer']),
        'Invalid selected prayer.',
      );
      final target = _integer(state['customTarget'], 1, 1000);
      _integer(state['customCount'], 0, target);
      if (state.containsKey('restoredDay')) _daily(_map(state['restoredDay']));
      final settings = _map(data['settings']);
      final vibration = _integer(settings['vibrationIntensity'], 0, 100);
      _require(vibration % 5 == 0, 'Invalid vibration intensity.');
      _require(
        ['prayer', 'custom'].contains(settings['mode']),
        'Invalid app mode.',
      );
      _require(
        ['classic', 'modern'].contains(settings['style']),
        'Invalid counter style.',
      );
      return ValidatedBackup._(
        timestamp,
        root['appVersion'] as String,
        jsonEncode(data),
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(
        'Invalid backup JSON or missing required fields.',
      );
    }
  }

  void _daily(Map<String, dynamic> state) {
    final date = _date(state['date']);
    final streak = _integer(state['streak'], 0, 2147483647);
    _require(state.containsKey('lastStreakDate'), 'Missing streak metadata.');
    if (state['lastStreakDate'] != null) {
      final last = _date(state['lastStreakDate']);
      _require(
        last.compareTo(date) <= 0,
        'Streak date cannot follow progress date.',
      );
    }
    _require(
      streak == 0 || state['lastStreakDate'] != null,
      'Missing successful streak date.',
    );
    final prayers = _map(state['prayers']);
    _require(
      prayers.length == config.prayers.length,
      'Prayer configuration is incompatible.',
    );
    for (final prayer in config.prayers) {
      final p = _map(prayers[prayer.id]);
      final duas = config.forPrayer(prayer.id);
      _require(
        duas.any((d) => d.id == p['selectedDuaId']),
        'Invalid selected Dhikr.',
      );
      final counts = _map(p['counts']);
      for (final entry in counts.entries) {
        _require(
          duas.any((d) => d.id == entry.key),
          'Unknown Dhikr in backup.',
        );
        _integer(entry.value, 0, 2147483647);
      }
      final completed = p['completed'];
      _require(
        completed is List && completed.every((v) => v is String),
        'Invalid completion list.',
      );
      final ids = (completed as List).cast<String>();
      _require(
        ids.toSet().length == ids.length,
        'Duplicate completion entries.',
      );
      for (final id in ids) {
        _require(
          duas.any((d) => d.id == id && (counts[id] ?? 0) >= d.target),
          'Completion does not match count.',
        );
      }
      for (final d in duas) {
        _require(
          ((counts[d.id] ?? 0) >= d.target) == ids.contains(d.id),
          'Incomplete completion metadata.',
        );
      }
    }
    // A complete valid app day has already been evaluated once. Rejecting
    // inconsistent metadata prevents import from awarding an artificial streak.
    final eligible = config.prayers.every(
      (p) =>
          (_map(prayers[p.id])['completed'] as List).length >=
          config.minimumStreakDuas,
    );
    _require(
      !eligible || (state['lastStreakDate'] == date && streak > 0),
      'Completed day is missing its streak evaluation.',
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    _require(value is Map<String, dynamic>, 'Missing required backup object.');
    return value as Map<String, dynamic>;
  }

  static int _integer(dynamic value, int min, int max) {
    _require(
      value is int && value >= min && value <= max,
      'Invalid counter or numeric setting.',
    );
    return value as int;
  }

  static String _date(dynamic value) {
    _require(
      value is String && RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(value),
      'Invalid progress date.',
    );
    final parsed = DateTime.tryParse(value as String);
    _require(
      parsed != null && parsed.year >= 1 && dateKey(parsed) == value,
      'Invalid calendar date.',
    );
    return value;
  }

  static void _require(bool valid, String message) {
    if (!valid) throw BackupException(message);
  }
}

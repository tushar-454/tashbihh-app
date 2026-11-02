import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/tasbih_config.dart';
import '../models/app_state.dart';

abstract class SnapshotStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesStore implements SnapshotStore {
  PreferencesStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'tasbih.native.snapshot.v1';
  @override
  Future<String?> read() async => preferences.getString(key);
  @override
  Future<void> write(String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Could not save progress');
    }
  }
}

class ProgressRepository {
  ProgressRepository(this.store);
  final SnapshotStore store;
  Future<(AppState, AppSettings)> load(
    TasbihConfig config,
    DateTime now,
  ) async {
    try {
      final raw = await store.read();
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] == 1) {
          return (
            AppState.fromJson(config, json['state']),
            AppSettings.fromJson(json['settings']),
          );
        }
      }
    } catch (_) {
      // A corrupt/unknown snapshot must never prevent offline startup.
    }
    return (AppState.empty(config, now), AppSettings());
  }

  String encode(AppState state, AppSettings settings) => jsonEncode({
    'version': 1,
    'state': state.toJson(),
    'settings': settings.toJson(),
  });
  Future<void> save(String snapshot) => store.write(snapshot);
}

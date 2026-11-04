import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/tasbih_config.dart';
import '../models/app_state.dart';
import '../localization/app_localizations.dart';

abstract class SnapshotStore {
  Future<String?> read();
  Future<void> write(String value);
}

abstract class ReplacementSnapshotStore implements SnapshotStore {
  Future<void> writeReplacement(String value);
}

class PreferencesStore implements SnapshotStore {
  PreferencesStore(this.preferences, {this.storageKey = key});
  final SharedPreferences preferences;
  static const key = 'tasbih.native.snapshot.v1';
  final String storageKey;
  @override
  Future<String?> read() async => preferences.getString(storageKey);
  @override
  Future<void> write(String value) async {
    if (!await preferences.setString(storageKey, value)) {
      throw StateError(const AppMessage('save_failed').english);
    }
  }
}

class ProgressRepository {
  ProgressRepository(this.store);
  final SnapshotStore store;
  Map<String, dynamic> cloudMetadata = {};
  Future<(AppState, AppSettings)> load(
    TasbihConfig config,
    DateTime now,
  ) async {
    try {
      final raw = await store.read();
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] == 1) {
          final state = AppState.fromJson(config, json['state']);
          final settings = AppSettings.fromJson(json['settings']);
          cloudMetadata = json['cloud'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(json['cloud'])
              : {};
          return (state, settings);
        }
      }
    } catch (_) {
      // A corrupt/unknown snapshot must never prevent offline startup.
    }
    return (AppState.empty(config, now), AppSettings());
  }

  String encode(
    AppState state,
    AppSettings settings, {
    Map<String, dynamic>? cloud,
  }) => jsonEncode({
    'version': 1,
    'cloud': cloud ?? cloudMetadata,
    'state': state.toJson(),
    'settings': settings.toJson(),
  });

  /// One native preference key is the commit unit. Restore the prior snapshot
  /// on a reported failure (including the SharedPreferences in-memory cache).
  Future<void> replace(
    String snapshot,
    String fallback, {
    bool newProgress = false,
  }) async {
    final previous = await store.read() ?? fallback;
    try {
      if (newProgress && store is ReplacementSnapshotStore) {
        await (store as ReplacementSnapshotStore).writeReplacement(snapshot);
      } else {
        await store.write(snapshot);
      }
    } catch (_) {
      try {
        await store.write(previous);
      } catch (_) {
        throw StateError(const AppMessage('restore_storage_failed').english);
      }
      rethrow;
    }
  }

  Future<void> save(String snapshot) => store.write(snapshot);

  /// A count captured while a cloud metadata write was pending must carry the
  /// newly committed metadata when its turn in the write queue arrives.
  Future<void> saveProgress(String snapshot) {
    final data = jsonDecode(snapshot) as Map<String, dynamic>;
    data['cloud'] = cloudMetadata;
    return store.write(jsonEncode(data));
  }
}

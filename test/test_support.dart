import 'dart:convert';
import 'dart:io';

import 'package:tashbihh/core/config/tasbih_config.dart';
import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/platform/device_services.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';

TasbihConfig testConfig() => TasbihConfig.fromJson(
  jsonDecode(File('assets/data/config.json').readAsStringSync()),
);

class MemoryStore implements SnapshotStore {
  String? value;
  bool fail = false;
  final List<String> writes = [];
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    if (fail) throw const FileSystemException('disk full');
    value = data;
    writes.add(data);
  }
}

class TestDevice extends DeviceServices {
  bool full = false;
  int taps = 0;
  @override
  bool get fullscreen => full;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> toggleFullscreen() async {
    full = !full;
    notifyListeners();
  }

  @override
  Future<void> feedback(int milliseconds, {required bool completed}) async {
    if (milliseconds > 0) taps++;
  }

  @override
  void cancelFeedback() {}
}

class Harness {
  Harness({DateTime? date}) {
    now = date ?? DateTime(2026, 11, 2, 5);
    config = testConfig();
    repository = ProgressRepository(store);
    controller = CounterController(
      config: config,
      repository: repository,
      state: AppState.empty(config, now),
      settings: AppSettings(),
      clock: () => now,
    );
  }
  late DateTime now;
  late TasbihConfig config;
  final store = MemoryStore();
  late ProgressRepository repository;
  late CounterController controller;
  void completeDay() {
    for (final prayer in config.prayers) {
      now = DateTime(
        now.year,
        now.month,
        now.day,
        prayer.start ~/ 60,
        prayer.start % 60,
      );
      controller.refresh();
      for (final dua in config.forPrayer(prayer.id).take(3)) {
        controller.selectDua(dua.id);
        for (var i = 0; i < dua.target; i++) {
          controller.increment();
        }
      }
    }
  }
}

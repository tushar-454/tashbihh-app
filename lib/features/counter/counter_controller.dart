import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/tasbih_config.dart';
import '../../core/backup/backup_service.dart';
import '../../core/models/app_state.dart';
import '../../core/storage/progress_repository.dart';
import '../streak/streak_rules.dart';

typedef Clock = DateTime Function();

class CounterController extends ChangeNotifier {
  CounterController({
    required this.config,
    required this.repository,
    required this.state,
    required this.settings,
    Clock? clock,
  }) : clock = clock ?? DateTime.now {
    now = this.clock();
    refresh();
  }
  final TasbihConfig config;
  final ProgressRepository repository;
  final Clock clock;
  AppState state;
  AppSettings settings;
  late DateTime now;
  Timer? _heartbeat;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool restoring = false;
  bool _clockRunning = false;
  String? storageError;
  bool get isCustom => settings.mode == AppMode.custom;
  PrayerProgress get progress => state.prayers[state.selectedPrayer]!;
  Dhikr get dua => config
      .forPrayer(state.selectedPrayer)
      .firstWhere((d) => d.id == progress.selectedDuaId);
  int get count =>
      isCustom ? state.customCount : (progress.counts[dua.id] ?? 0);
  int get target => isCustom ? state.customTarget : dua.target;
  String? get activePrayer => config.activePrayer(now);
  bool get done => count >= target;
  bool completed(Dhikr d) => (progress.counts[d.id] ?? 0) >= d.target;
  bool canSelect(String prayer) =>
      isCustom || activePrayer == null || activePrayer == prayer;
  bool get canCount =>
      !restoring &&
      !done &&
      (isCustom || (config.schedule.eligible(state.selectedPrayer, now)));
  String get counterHint {
    if (done) {
      return isCustom
          ? 'Target completed. Double tap to reset.'
          : 'Target completed';
    }
    if (isCustom) return 'Tap to count. Double tap to reset.';
    if (activePrayer != state.selectedPrayer) {
      return 'Not available at this time · ${config.prayer(state.selectedPrayer).windowLabel}';
    }
    return 'Available now. Tap to count. Double tap to reset incomplete progress.';
  }

  void stopClock() {
    _clockRunning = false;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void startClock() {
    _clockRunning = true;
    refresh();
  }

  void _scheduleRefresh() {
    _heartbeat?.cancel();
    if (!_clockRunning || _disposed) return;
    final until = config.schedule.nextTransition(now).difference(now);
    // Exact boundaries plus a low-frequency fallback for platforms without
    // Android clock-change broadcasts. No background polling.
    final delay = until < const Duration(minutes: 1)
        ? until
        : const Duration(minutes: 1);
    _heartbeat = Timer(delay, refresh);
  }

  void refresh({bool autoSelect = true}) {
    if (restoring) return;
    now = clock();
    _scheduleRefresh();
    var changed = StreakRules.rollForward(state, config, now);
    final active = activePrayer;
    if (autoSelect &&
        !isCustom &&
        active != null &&
        state.selectedPrayer != active) {
      state.selectedPrayer = active;
      changed = true;
    }
    if (changed) _persist();
    if (!_disposed) notifyListeners();
  }

  bool increment() {
    // Do not change a deliberately selected inactive prayer just to count it.
    refresh(autoSelect: false);
    if (!canCount) return false;
    if (isCustom) {
      state.customCount += 1;
    } else {
      final next = count + 1;
      progress.counts[dua.id] = next;
      if (next >= dua.target) progress.completed.add(dua.id);
      StreakRules.evaluate(state, config, now);
    }
    _changed();
    return true;
  }

  void selectPrayer(String id) {
    if (restoring) return;
    refresh(autoSelect: false);
    if (!config.prayers.any((p) => p.id == id) || !canSelect(id)) return;
    state.selectedPrayer = id;
    _changed();
  }

  void selectDua(String id) {
    if (restoring) return;
    refresh(autoSelect: false);
    if (!config.forPrayer(state.selectedPrayer).any((d) => d.id == id)) return;
    progress.selectedDuaId = id;
    _changed();
  }

  void resetCounter() {
    if (restoring) return;
    refresh(autoSelect: false);
    if (isCustom) {
      state.customCount = 0;
    } else {
      if (progress.completed.contains(dua.id)) return;
      progress.counts[dua.id] = 0;
    }
    _changed();
  }

  void toggleMode() {
    if (restoring) return;
    refresh(autoSelect: false);
    settings.mode = isCustom ? AppMode.prayer : AppMode.custom;
    refresh();
    _changed();
  }

  void toggleStyle() {
    if (restoring) return;
    settings.style = settings.style == CounterStyle.classic
        ? CounterStyle.modern
        : CounterStyle.classic;
    _changed();
  }

  void setIntensity(int value) {
    if (restoring) return;
    settings.vibrationIntensity = value.clamp(0, 100) ~/ 5 * 5;
    _changed();
  }

  void setCustomTarget(int value) {
    if (restoring) return;
    state.customTarget = (value.clamp(10, 1000) / 10).round() * 10;
    state.customCount = state.customCount.clamp(0, state.customTarget);
    _changed();
  }

  Future<void> resetAll() async {
    if (restoring) return;
    state = AppState.empty(config, clock());
    settings = AppSettings();
    storageError = null;
    now = clock();
    _changed();
    await flush();
  }

  Future<void> restore(ValidatedBackup backup) async {
    if (restoring) throw StateError('A restore is already running.');
    restoring = true;
    notifyListeners();
    try {
      await flush();
      final candidate = backup.state(config);
      final restoredSettings = backup.settings;
      final localNow = clock();
      if (candidate.date.compareTo(dateKey(localNow)) > 0) {
        throw const BackupException(
          'Backup progress is dated in the future. Check the device date before restoring.',
        );
      }
      if (candidate.date != dateKey(localNow)) {
        candidate.restoredDay = {
          'date': candidate.date,
          'prayers': {
            for (final p in candidate.prayers.entries) p.key: p.value.toJson(),
          },
          'streak': candidate.streak,
          'lastStreakDate': candidate.lastStreakDate,
        };
      }
      StreakRules.rollForward(candidate, config, localNow);
      final active = config.schedule.activePrayer(localNow);
      if (restoredSettings.mode == AppMode.prayer && active != null) {
        candidate.selectedPrayer = active;
      }
      await repository.replace(
        repository.encode(candidate, restoredSettings),
        repository.encode(state, settings),
      );
      state = candidate;
      settings = restoredSettings;
      now = localNow;
      storageError = null;
    } finally {
      restoring = false;
      if (!_disposed) {
        refresh();
      }
    }
  }

  void _changed() {
    _persist();
    if (!_disposed) notifyListeners();
  }

  void _persist() {
    // Capture synchronously; serialize writes so an earlier slow write cannot
    // overwrite a newer count/settings/reset snapshot.
    final snapshot = repository.encode(state, settings);
    _writes = _writes.then((_) async {
      try {
        await repository.save(snapshot);
        if (storageError != null) {
          storageError = null;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {
        storageError =
            'Progress could not be saved. Please free device storage.';
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> flush() => _writes;
  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    super.dispose();
  }
}

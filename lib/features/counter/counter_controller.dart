import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/tasbih_config.dart';
import '../../core/backup/backup_service.dart';
import '../../core/models/app_state.dart';
import '../../core/storage/progress_repository.dart';
import '../../core/prayer/prayer_time_sync.dart';
import '../../core/time/prayer_schedule.dart';
import '../streak/streak_rules.dart';

typedef Clock = DateTime Function();

class CounterController extends ChangeNotifier {
  CounterController({
    required this.config,
    required this.repository,
    required this.state,
    required this.settings,
    Clock? clock,
    this.prayerTimes,
  }) : clock = clock ?? DateTime.now {
    now = this.clock();
    prayerTimes?.addListener(_scheduleChanged);
    refresh();
  }
  final TasbihConfig config;
  final ProgressRepository repository;
  final Clock clock;
  final PrayerTimeSync? prayerTimes;
  PrayerSchedule get schedule =>
      prayerTimes?.scheduleFor(now) ?? config.schedule;
  void _scheduleChanged() => refresh();
  AppState state;
  AppSettings settings;
  late DateTime now;
  Timer? _heartbeat;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  bool restoring = false;
  bool cloudLocked = false;
  bool get dataLocked => restoring || cloudLocked;
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
  String? get activePrayer => schedule.activePrayer(now);
  bool get done => count >= target;
  bool completed(Dhikr d) => (progress.counts[d.id] ?? 0) >= d.target;
  bool canSelect(String prayer) =>
      isCustom || activePrayer == null || activePrayer == prayer;
  bool get canCount =>
      !dataLocked &&
      !done &&
      (isCustom || (schedule.eligible(state.selectedPrayer, now)));
  String get counterHint {
    if (done) {
      return isCustom
          ? 'Target completed. Double tap to reset.'
          : 'Target completed';
    }
    if (isCustom) return 'Tap to count. Double tap to reset.';
    if (activePrayer != state.selectedPrayer) {
      return 'Not available at this time · ${schedule.windowLabel(state.selectedPrayer)}';
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
    final until = schedule.nextTransition(now).difference(now);
    // Exact boundaries plus a low-frequency fallback for platforms without
    // Android clock-change broadcasts. No background polling.
    final delay = until < const Duration(minutes: 1)
        ? until
        : const Duration(minutes: 1);
    _heartbeat = Timer(delay, refresh);
  }

  void refresh({bool autoSelect = true}) {
    if (dataLocked) return;
    now = clock();
    prayerTimes?.observeClock(now);
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
    if (dataLocked) return;
    refresh(autoSelect: false);
    if (!config.prayers.any((p) => p.id == id) || !canSelect(id)) return;
    state.selectedPrayer = id;
    _changed();
  }

  void selectDua(String id) {
    if (dataLocked) return;
    refresh(autoSelect: false);
    if (!config.forPrayer(state.selectedPrayer).any((d) => d.id == id)) return;
    progress.selectedDuaId = id;
    _changed();
  }

  void resetCounter() {
    if (dataLocked) return;
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
    if (dataLocked) return;
    refresh(autoSelect: false);
    settings.mode = isCustom ? AppMode.prayer : AppMode.custom;
    refresh();
    _changed();
  }

  void toggleStyle() {
    if (dataLocked) return;
    settings.style = settings.style == CounterStyle.classic
        ? CounterStyle.modern
        : CounterStyle.classic;
    _changed();
  }

  void setIntensity(int value) {
    if (dataLocked) return;
    settings.vibrationIntensity = value.clamp(0, 100) ~/ 5 * 5;
    _changed();
  }

  void setCustomTarget(int value) {
    if (dataLocked) return;
    state.customTarget = (value.clamp(10, 1000) / 10).round() * 10;
    state.customCount = state.customCount.clamp(0, state.customTarget);
    _changed();
  }

  Future<void> resetAll() => commitCloud(reset: true);

  Future<void> restore(ValidatedBackup backup) => commitCloud(backup: backup);

  /// Ordinary uploads save bookkeeping through the progress write queue without
  /// freezing taps. Later count writes inherit the committed cloud metadata.
  Future<void> saveCloudMetadata(Map<String, dynamic> metadata) {
    final result = _writes.then((_) async {
      await repository.replace(
        repository.encode(state, settings, cloud: metadata),
        repository.encode(state, settings),
      );
      repository.cloudMetadata = Map.of(metadata);
    });
    // A reported metadata error must not poison later counter persistence.
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Progress and cloud identity share one durable commit unit. No account can
  /// become active with another account's data after an interrupted transition.
  Future<void> commitCloud({
    ValidatedBackup? backup,
    Map<String, dynamic>? metadata,
    bool reset = false,
  }) async {
    if (restoring) throw StateError('A restore is already running.');
    restoring = true;
    notifyListeners();
    try {
      await flush();
      final candidate = reset
          ? AppState.empty(config, clock())
          : backup?.state(config) ?? state;
      final restoredSettings = reset
          ? AppSettings()
          : backup?.settings ?? settings;
      final localNow = clock();
      if (backup != null || reset) {
        if (candidate.date.compareTo(dateKey(localNow)) > 0) {
          throw const BackupException(
            'Backup progress is dated in the future. Check the device date before restoring.',
          );
        }
        if (candidate.date != dateKey(localNow)) {
          candidate.restoredDay = {
            'date': candidate.date,
            'prayers': {
              for (final p in candidate.prayers.entries)
                p.key: p.value.toJson(),
            },
            'streak': candidate.streak,
            'lastStreakDate': candidate.lastStreakDate,
          };
        }
        StreakRules.rollForward(candidate, config, localNow);
        final active = (prayerTimes?.scheduleFor(localNow) ?? config.schedule)
            .activePrayer(localNow);
        if (restoredSettings.mode == AppMode.prayer && active != null) {
          candidate.selectedPrayer = active;
        }
      }
      await repository.replace(
        repository.encode(candidate, restoredSettings, cloud: metadata),
        repository.encode(state, settings),
      );
      if (metadata != null) repository.cloudMetadata = Map.of(metadata);
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
        await repository.saveProgress(snapshot);
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
    prayerTimes?.removeListener(_scheduleChanged);
    prayerTimes?.dispose();
    super.dispose();
  }
}

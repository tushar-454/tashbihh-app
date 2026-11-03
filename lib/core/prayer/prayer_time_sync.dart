import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/tasbih_config.dart';
import '../models/app_state.dart';
import '../time/prayer_schedule.dart';
import 'aladhan_client.dart';
import 'prayer_location.dart';
import 'prayer_times.dart';
import 'prayer_times_repository.dart';

/// Foreground-only daily synchronization. Counter timers observe the local day;
/// this class only schedules two bounded retries (5 and 30 minutes) on failure.
class PrayerTimeSync extends ChangeNotifier {
  PrayerTimeSync({
    required this.config,
    required this.repository,
    required this.location,
    required this.api,
    required this.readTimeZone,
    DateTime Function()? clock,
    this.calculation = const PrayerCalculation(),
  }) : clock = clock ?? DateTime.now;

  final TasbihConfig config;
  final PrayerTimesRepository repository;
  final PrayerLocation location;
  final PrayerTimesApi api;
  final Future<String> Function() readTimeZone;
  final DateTime Function() clock;
  final PrayerCalculation calculation;
  PrayerTimes? _cached;
  PrayerSchedule? _cachedSchedule;
  String? _deviceZone;
  String? message;
  String? _observedDay;
  Future<void>? _inFlight;
  Timer? _retry;
  int _failures = 0;
  bool _foreground = false, _disposed = false;
  LocationExplanation? _explain;
  bool _recheck = false;

  bool get syncing => _inFlight != null;
  PrayerTimes? get cached => _cached;
  String _daySignature(DateTime now) =>
      '${dateKey(now)}|${now.timeZoneName}|${now.timeZoneOffset.inMinutes}';

  /// Local disk + a small Android timezone query only. No GPS or network here.
  Future<void> load() async {
    _cached = await repository.load();
    _cachedSchedule = _cached?.schedule(config);
    try {
      _deviceZone = await readTimeZone().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* JSON fallback. */
    }
    _observedDay = _daySignature(clock());
  }

  PrayerSchedule scheduleFor(DateTime now) =>
      _deviceZone != null &&
          _cached?.canReuseFor(now, _deviceZone!, calculation) == true
      ? _cachedSchedule!
      : config.schedule;

  String get _fallbackMessage =>
      identical(scheduleFor(clock()), config.schedule)
      ? 'Using configured prayer times.'
      : 'Using saved prayer times from ${_cached!.date}.';

  void resume(LocationExplanation explain) {
    if (_disposed) return;
    if (!_foreground && _inFlight != null) _recheck = true;
    _foreground = true;
    _explain = explain;
    observeClock(clock());
    unawaited(synchronize());
  }

  void suspend() {
    _foreground = false;
    _retry?.cancel();
    _retry = null;
    unawaited(location.gateway.cancelPosition().catchError((Object _) {}));
  }

  /// Cheap synchronous check; minute ticks and counter taps never poll GPS/API.
  void observeClock(DateTime now) {
    final signature = _daySignature(now);
    if (signature == _observedDay) return;
    _observedDay = signature;
    _failures = 0;
    if (_foreground) unawaited(synchronize());
  }

  /// Also called for Android TIMEZONE_CHANGED, including equal-offset zones.
  void clockChanged() {
    if (_foreground) {
      // A broadcast may arrive while a response is being validated/saved.
      if (_inFlight != null) _recheck = true;
      unawaited(synchronize());
    }
  }

  Future<void> synchronize() {
    if (_disposed || !_foreground || _explain == null) return Future.value();
    if (_inFlight != null) return _inFlight!;
    final completed = Completer<void>();
    final signature = _daySignature(clock());
    _inFlight = completed.future;
    // Set the guard before the first await (including native timezone lookup).
    unawaited(
      _synchronize().whenComplete(() {
        _inFlight = null;
        completed.complete();
        final recheck = _recheck;
        _recheck = false;
        if (!_disposed &&
            _foreground &&
            (recheck || signature != _daySignature(clock()))) {
          unawaited(synchronize());
        }
      }),
    );
    return completed.future;
  }

  Future<void> _synchronize() async {
    final started = clock();
    final signature = _daySignature(started);
    try {
      final zone = await readTimeZone().timeout(const Duration(seconds: 2));
      if (_disposed) return;
      final zoneChanged = zone != _deviceZone;
      _deviceZone = zone;
      if (zoneChanged) notifyListeners();
      if (!_foreground) return;
      if (_cached?.validFor(clock(), zone, calculation) == true) {
        _retry?.cancel();
        _failures = 0;
        _setMessage(null);
        return;
      }
      await location.authorize(_explain!, () => _foreground && !_disposed);
      if (!_foreground || _disposed) return;
      if (!await location.gateway.servicesEnabled()) {
        throw const PrayerLocationException(
          'Turn on device Location in Android Settings to get local prayer times.',
        );
      }
      if (!_foreground || _disposed) return;
      final coordinates = await location.gateway.currentPosition();
      if (!_foreground || _disposed || signature != _daySignature(clock())) {
        return;
      }
      var schedule = await api.fetch(
        now: clock(),
        coordinates: coordinates,
        deviceTimezone: zone,
        calculation: calculation,
      );
      // Reject results arriving after midnight, timezone/clock changes or suspend.
      final currentZone = await readTimeZone().timeout(
        const Duration(seconds: 2),
      );
      if (currentZone != zone) {
        _deviceZone = currentZone;
        _recheck = true;
        if (!_disposed) notifyListeners();
      }
      if (!_foreground ||
          _disposed ||
          currentZone != zone ||
          !schedule.validFor(clock(), currentZone, calculation)) {
        return;
      }
      schedule = schedule.synchronizedAt(clock());
      await repository.save(schedule);
      if (_disposed) return;
      _cached = schedule;
      _cachedSchedule = schedule.schedule(config);
      _failures = 0;
      _retry?.cancel();
      message = null;
      notifyListeners();
    } on PrayerLocationException catch (error) {
      _setMessage('$_fallbackMessage ${error.message}');
      // Denials/GPS disabled retry on foreground resume or a new date only.
    } catch (_) {
      if (!_disposed && _foreground) {
        _setMessage(
          'Local prayer times are unavailable. $_fallbackMessage Automatic synchronization will retry later.',
        );
        _scheduleRetry();
      }
    }
  }

  void _setMessage(String? value) {
    if (_disposed || message == value) return;
    message = value;
    notifyListeners();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _failures++;
    if (!_foreground || _failures > 2) return;
    _retry = Timer(Duration(minutes: _failures == 1 ? 5 : 30), () {
      _retry = null;
      unawaited(synchronize());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    super.dispose();
  }
}

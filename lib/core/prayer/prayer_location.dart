import 'package:flutter/services.dart';
import 'package:geolocator_android/geolocator_android.dart';

import '../storage/progress_repository.dart';
import 'prayer_times.dart';

enum PrayerLocationAccess { granted, denied, permanentlyDenied }

class PrayerLocationException implements Exception {
  const PrayerLocationException(this.message);
  final String message;
}

abstract class PrayerLocationGateway {
  Future<PrayerLocationAccess> checkPermission();
  Future<PrayerLocationAccess> requestPermission();
  Future<bool> servicesEnabled();
  Future<PrayerCoordinates> currentPosition();
  Future<void> cancelPosition();
}

class AndroidPrayerLocation implements PrayerLocationGateway {
  final _geolocator = GeolocatorAndroid();
  String? _positionRequest;

  static Future<String> timeZoneId() async =>
      (await const MethodChannel('tasbih/local_timezone')
          .invokeMethod<String>('getTimeZone'))!;

  PrayerLocationAccess _access(LocationPermission value) => switch (value) {
    LocationPermission.whileInUse ||
    LocationPermission.always => PrayerLocationAccess.granted,
    LocationPermission.deniedForever => PrayerLocationAccess.permanentlyDenied,
    _ => PrayerLocationAccess.denied,
  };

  @override
  Future<PrayerLocationAccess> checkPermission() async =>
      _access(await _geolocator.checkPermission());
  @override
  Future<PrayerLocationAccess> requestPermission() async =>
      _access(await _geolocator.requestPermission());
  @override
  Future<bool> servicesEnabled() => _geolocator.isLocationServiceEnabled();
  @override
  Future<PrayerCoordinates> currentPosition() async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _positionRequest = id;
    try {
      final position = await _geolocator.getCurrentPosition(
        requestId: id,
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        ),
      );
      return PrayerCoordinates(position.latitude, position.longitude);
    } finally {
      if (_positionRequest == id) _positionRequest = null;
    }
  }

  @override
  Future<void> cancelPosition() async {
    final id = _positionRequest;
    if (id == null) return;
    _positionRequest = null;
    // geolocator_android's one-shot cancellation bridge, also used by its timeout.
    await const MethodChannel('flutter.baseflow.com/geolocator_android')
        .invokeMethod<void>('cancelGetCurrentPosition', {'requestId': id});
  }
}

typedef LocationExplanation = Future<bool> Function();

/// The marker is written BEFORE prompting. Denials and dismissed explanations
/// survive restarts. Permission changes in Android Settings are still detected.
class PrayerLocation {
  PrayerLocation(this.gateway, this.promptStore);
  final PrayerLocationGateway gateway;
  final SnapshotStore promptStore;
  bool _attemptedInSession = false;

  Future<void> authorize(
    LocationExplanation explain,
    bool Function() foreground,
  ) async {
    var permission = await gateway.checkPermission();
    if (permission == PrayerLocationAccess.denied &&
        !_attemptedInSession &&
        await promptStore.read() == null &&
        foreground()) {
      _attemptedInSession = true;
      await promptStore.write('requested');
      if (!foreground()) return;
      if (await explain() && foreground()) {
        permission = await gateway.requestPermission();
      }
    }
    if (permission != PrayerLocationAccess.granted) {
      throw const PrayerLocationException(
        'Using configured prayer times. To enable location, open Android Settings → Apps → Tasbih Counter → Permissions → Location and allow access while using the app.',
      );
    }
  }
}

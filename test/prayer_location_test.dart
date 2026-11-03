import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:tashbihh/core/prayer/prayer_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator_android');
  final calls = <MethodCall>[];
  late AndroidPrayerLocation location;
  var permission = LocationPermission.whileInUse;
  var enabled = true;
  Completer<Map<String, dynamic>>? pending;

  setUp(() {
    calls.clear();
    permission = LocationPermission.whileInUse;
    enabled = true;
    pending = null;
    location = AndroidPrayerLocation();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'checkPermission' || 'requestPermission' => permission.index,
            'isLocationServiceEnabled' => enabled,
            'getCurrentPosition' =>
              pending?.future ??
                  {
                    'latitude': 23.8103,
                    'longitude': 90.4125,
                    'timestamp': DateTime(2026, 11, 3).millisecondsSinceEpoch,
                    'accuracy': 100.0,
                    'altitude': 0.0,
                    'altitude_accuracy': 0.0,
                    'heading': 0.0,
                    'heading_accuracy': 0.0,
                    'speed': 0.0,
                    'speed_accuracy': 0.0,
                  },
            'cancelGetCurrentPosition' => null,
            _ => throw PlatformException(
              code: 'unexpected',
              message: call.method,
            ),
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android permission statuses map to foreground/denied/permanent states',
    () async {
      expect(await location.checkPermission(), PrayerLocationAccess.granted);
      permission = LocationPermission.denied;
      expect(await location.checkPermission(), PrayerLocationAccess.denied);
      permission = LocationPermission.deniedForever;
      expect(
        await location.requestPermission(),
        PrayerLocationAccess.permanentlyDenied,
      );
    },
  );
  test('detects disabled services and obtains one rounded position without a stream', () async {
    enabled = false;
    expect(await location.servicesEnabled(), isFalse);
    final coordinates = await location.currentPosition();
    expect(coordinates.latitude, 23.81);
    expect(coordinates.longitude, 90.413);
    expect(calls.map((c) => c.method), [
      'isLocationServiceEnabled',
      'getCurrentPosition',
    ]);
    final arguments = calls.last.arguments as Map;
    expect(arguments['foregroundNotificationConfig'], isNull);
    expect(arguments['accuracy'], LocationAccuracy.medium.index);
  });
  testWidgets(
    'one-shot GPS request times out and cancels native location work',
    (tester) async {
      pending = Completer<Map<String, dynamic>>();
      final result = location.currentPosition();
      final expectation = expectLater(result, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(seconds: 20));
      await expectation;
      expect(calls.map((c) => c.method), contains('cancelGetCurrentPosition'));
      final get = calls.firstWhere((c) => c.method == 'getCurrentPosition');
      final cancel = calls.firstWhere(
        (c) => c.method == 'cancelGetCurrentPosition',
      );
      expect(cancel.arguments['requestId'], get.arguments['requestId']);
      pending!.complete({'latitude': 0, 'longitude': 0});
    },
  );
  testWidgets('suspending cancels the same pending native request', (
    tester,
  ) async {
    pending = Completer<Map<String, dynamic>>();
    final result = location.currentPosition();
    await tester.pump();
    await location.cancelPosition();
    expect(calls.last.method, 'cancelGetCurrentPosition');
    pending!.complete({'latitude': 23.81, 'longitude': 90.413});
    await result;
  });
}

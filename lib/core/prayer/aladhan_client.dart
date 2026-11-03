import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prayer_times.dart';

abstract class PrayerTimesApi {
  Future<PrayerTimes> fetch({
    required DateTime now,
    required PrayerCoordinates coordinates,
    required String deviceTimezone,
    required PrayerCalculation calculation,
  });
}

class AladhanClient implements PrayerTimesApi {
  AladhanClient({http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() clientFactory;

  @override
  Future<PrayerTimes> fetch({
    required DateTime now,
    required PrayerCoordinates coordinates,
    required String deviceTimezone,
    required PrayerCalculation calculation,
  }) async {
    final uri = Uri.https(
      'api.aladhan.com',
      '/v1/timings/${PrayerTimes.apiDate(now)}',
      {
        'latitude': '${coordinates.latitude}',
        'longitude': '${coordinates.longitude}',
        'method': '${calculation.method}',
        'school': '${calculation.school}',
      },
    );
    final client = clientFactory();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.length > 100000) {
        throw const FormatException('Prayer server unavailable');
      }
      return PrayerTimes.fromApi(
        jsonDecode(response.body) as Map<String, dynamic>,
        requestedAt: now,
        coordinates: coordinates,
        deviceTimezone: deviceTimezone,
        calculation: calculation,
      );
    } finally {
      // Closing also aborts the underlying request on timeout.
      client.close();
    }
  }
}

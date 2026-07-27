import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Open-Meteo current conditions for a run location.
class WeatherSnapshot {
  final double temperatureC;
  final double humidityPct;
  final double? windSpeedMps;
  /// Meteorological direction the wind comes from (0 = north, 90 = east).
  final double? windFromDeg;
  final double? pressureHpa;

  const WeatherSnapshot({
    required this.temperatureC,
    required this.humidityPct,
    this.windSpeedMps,
    this.windFromDeg,
    this.pressureHpa,
  });
}

class WeatherService {
  final HttpClient _client;

  WeatherService({HttpClient? client}) : _client = client ?? HttpClient();

  /// Headwind along [headingDeg] (direction of travel). Positive = headwind.
  static double? headwindMps({
    required double? windSpeedMps,
    required double? windFromDeg,
    required double? headingDeg,
  }) {
    if (windSpeedMps == null || windFromDeg == null || headingDeg == null) {
      return null;
    }
    final delta =
        _normalizeDeg(windFromDeg - headingDeg) * math.pi / 180.0;
    return windSpeedMps * math.cos(delta);
  }

  static double _normalizeDeg(double deg) {
    var d = deg % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  Future<WeatherSnapshot?> fetchWeather(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,'
        'wind_speed_10m,wind_direction_10m,surface_pressure'
        '&wind_speed_unit=ms',
      );
      final request =
          await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body);
        final current = data['current'];
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toDouble();
          final humid =
              (current['relative_humidity_2m'] as num?)?.toDouble();
          if (temp != null && humid != null) {
            return WeatherSnapshot(
              temperatureC: temp,
              humidityPct: humid,
              windSpeedMps:
                  (current['wind_speed_10m'] as num?)?.toDouble(),
              windFromDeg:
                  (current['wind_direction_10m'] as num?)?.toDouble(),
              pressureHpa:
                  (current['surface_pressure'] as num?)?.toDouble(),
            );
          }
        }
      } else {
        // ignore: avoid_print
        print(
          '[WeatherService] Non-200 response from Open-Meteo: ${response.statusCode}',
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[WeatherService] Error fetching weather: $e');
    }
    return null;
  }
}

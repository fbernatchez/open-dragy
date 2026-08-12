import 'dart:convert';
import 'dart:io';

class WeatherService {
  final HttpClient _client;

  WeatherService({HttpClient? client}) : _client = client ?? HttpClient();

  /// Fetches weather data (temperature in Celsius and relative humidity percentage)
  /// from the free keyless Open-Meteo weather API using GPS coordinates.
  /// Returns a map with 'temp' and 'humid' keys, or null if the request fails or times out.
  Future<Map<String, double>?> fetchWeather(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code',
      );
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body);
        final current = data['current'];
        if (current != null) {
          final temp = (current['temperature_2m'] as num?)?.toDouble();
          final humid = (current['relative_humidity_2m'] as num?)?.toDouble();
          final weatherCode = (current['weather_code'] as num?)?.toInt();
          if (temp != null && humid != null) {
            return {
              'temp': temp,
              'humid': humid,
              if (weatherCode != null) 'weatherCode': weatherCode.toDouble(),
            };
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/services/weather_service.dart';

class MockHttpClient implements HttpClient {
  final MockHttpClientRequest request;
  bool isClosed = false;

  MockHttpClient(this.request);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;

  @override
  void close({bool force = false}) {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) return null;
    return super.noSuchMethod(invocation);
  }
}

class MockHttpClientRequest implements HttpClientRequest {
  final MockHttpClientResponse response;

  MockHttpClientRequest(this.response);

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #close) return null;
    return super.noSuchMethod(invocation);
  }
}

class MockHttpClientResponse implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockHttpClientResponse(this.statusCode, this.body);

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    final byteStream = Stream.value(utf8.encode(body));
    return streamTransformer.bind(byteStream);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('WeatherService Tests', () {
    test('fetches weather and parses successfully on 200 OK', () async {
      final jsonString = json.encode({
        'current': {
          'temperature_2m': 22.5,
          'relative_humidity_2m': 55.0,
        }
      });
      final mockResponse = MockHttpClientResponse(200, jsonString);
      final mockRequest = MockHttpClientRequest(mockResponse);
      final mockClient = MockHttpClient(mockRequest);

      final service = WeatherService(client: mockClient);
      final result = await service.fetchWeather(37.7749, -122.4194);

      expect(result, isNotNull);
      expect(result!.temperatureC, 22.5);
      expect(result.humidityPct, 55.0);
    });

    test('parses wind and pressure when present', () async {
      final jsonString = json.encode({
        'current': {
          'temperature_2m': 18.0,
          'relative_humidity_2m': 40.0,
          'wind_speed_10m': 3.5,
          'wind_direction_10m': 180.0,
          'surface_pressure': 1012.0,
        }
      });
      final mockResponse = MockHttpClientResponse(200, jsonString);
      final mockRequest = MockHttpClientRequest(mockResponse);
      final mockClient = MockHttpClient(mockRequest);

      final service = WeatherService(client: mockClient);
      final result = await service.fetchWeather(50.0, 14.0);

      expect(result, isNotNull);
      expect(result!.windSpeedMps, 3.5);
      expect(result.windFromDeg, 180.0);
      expect(result.pressureHpa, 1012.0);
      expect(
        WeatherService.headwindMps(
          windSpeedMps: 3.5,
          windFromDeg: 180,
          headingDeg: 180,
        ),
        closeTo(3.5, 0.01),
      );
      expect(
        WeatherService.headwindMps(
          windSpeedMps: 3.5,
          windFromDeg: 180,
          headingDeg: 0,
        ),
        closeTo(-3.5, 0.01),
      );
    });

    test('returns null gracefully on non-200 status code', () async {
      final mockResponse = MockHttpClientResponse(500, 'Internal Server Error');
      final mockRequest = MockHttpClientRequest(mockResponse);
      final mockClient = MockHttpClient(mockRequest);

      final service = WeatherService(client: mockClient);
      final result = await service.fetchWeather(37.7749, -122.4194);

      expect(result, isNull);
    });

    test('returns null gracefully on network exception/timeout', () async {
      final mockClient = MockHttpClient(MockHttpClientRequest(MockHttpClientResponse(200, '')));
      // Force getUrl to throw SocketException
      final service = WeatherService(client: mockClient);
      
      // We can trigger an exception by passing bad inputs or since mock can be configured
      // but let's test a mock client that throws directly in getUrl
      final throwingClient = MockHttpClientThrowing();
      final errorService = WeatherService(client: throwingClient);
      
      final result = await errorService.fetchWeather(37.7749, -122.4194);
      expect(result, isNull);
    });
  });
}

class MockHttpClientThrowing implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('Connection timed out');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

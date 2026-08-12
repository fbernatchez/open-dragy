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
      expect(result!['temp'], 22.5);
      expect(result['humid'], 55.0);
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

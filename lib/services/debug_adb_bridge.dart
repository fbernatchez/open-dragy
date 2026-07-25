import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/dragy_provider.dart';
import '../screens/satellite_status_screen.dart';

/// ADB-controllable debug hooks (debug builds).
///
/// Examples:
/// ```
/// adb shell am broadcast -a com.fb_engineering.open_dragy.debug.DEBUG_CMD --es cmd satellites
/// adb shell am start -a android.intent.action.VIEW -d "opendragy://debug/status"
/// ```
class DebugAdbBridge {
  DebugAdbBridge._();

  static const _channel = MethodChannel('opendragy/debug');
  static final navigatorKey = GlobalKey<NavigatorState>();

  static bool get enabled => kDebugMode;

  static void install() {
    if (!enabled) return;
    _channel.setMethodCallHandler(_onMethodCall);
    log('ADB debug bridge ready');
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    final cmd = call.method;
    final args = call.arguments;
    final Map<String, dynamic> params = args is Map
        ? args.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    log('ADB cmd=$cmd args=$params');
    return _handle(cmd, params);
  }

  static Future<String> _handle(
    String cmd,
    Map<String, dynamic> params,
  ) async {
    switch (cmd) {
      case 'ping':
        return 'pong';
      case 'status':
        return _dumpStatus();
      case 'satellites':
      case 'sky':
      case 'map':
        await _openMap();
        return 'opened map';
      case 'pubx_poll':
        return _pubxPoll();
      case 'dashboard':
        await _popToRoot();
        return 'dashboard';
      case 'deep_link':
        final uri = Uri.tryParse(params['uri']?.toString() ?? '');
        if (uri == null) return 'bad uri';
        return _handleDeepLink(uri);
      default:
        log('unknown cmd: $cmd');
        return 'unknown:$cmd';
    }
  }

  static Future<String> _handleDeepLink(Uri uri) async {
    // opendragy://debug/<cmd>
    if (uri.host != 'debug' && uri.pathSegments.isEmpty) {
      return 'ignored';
    }
    final cmd = uri.host == 'debug'
        ? (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'ping')
        : uri.host;
    if (cmd == 'satellites' || cmd == 'sky' || cmd == 'map') {
      await _openMap();
      return 'opened map';
    }
    return _handle(cmd, Map<String, dynamic>.from(uri.queryParameters));
  }

  static Future<void> _openMap() async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      log('navigator not ready');
      return;
    }
    await nav.push(
      MaterialPageRoute(builder: (_) => const SatelliteStatusScreen()),
    );
  }

  static Future<void> _popToRoot() async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  /// Probe whether GPS accepts NMEA input (`$PUBX,00`).
  static Future<String> _pubxPoll() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return 'no context';
    final ble = ctx.read<DragyProvider>().bleService;
    // $PUBX,00*33\r\n
    final ok = await ble.writeToGps(
      '\$PUBX,00*33\r\n'.codeUnits,
    );
    log('PUBX,00 poll write ok=$ok — watch for [BLE] NMEA PUBX');
    return 'pubx_poll ok=$ok';
  }

  static String _dumpStatus() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return 'no context';
    final d = ctx.read<DragyProvider>();
    final summary = {
      'connected': d.isConnected,
      'sats': d.satellites,
      'hdop': d.hdop,
      'fix': d.fixQuality,
      'lat': d.latitude,
      'lon': d.longitude,
      'alt': d.altitude,
      'speedKmh': d.metrics.speedKmh,
    };
    final line = summary.entries.map((e) => '${e.key}=${e.value}').join(' ');
    log('STATUS $line');
    return line;
  }

  static void log(String message) {
    developer.log(message, name: 'OpenDragy');
    // ignore: avoid_print
    print('[OpenDragy] $message');
  }
}

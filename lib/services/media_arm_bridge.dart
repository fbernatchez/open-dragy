import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef MediaArmHandler = FutureOr<void> Function();
typedef MediaDragTargetHandler = FutureOr<void> Function(String name);
typedef MediaVehicleHandler = FutureOr<void> Function(String id);

/// Android MediaSession / AA bridge: Next→ARM toggle, Previous→DISARM.
class MediaArmBridge {
  MediaArmBridge._();
  static final MediaArmBridge instance = MediaArmBridge._();

  static const _channel = MethodChannel('opendragy/media_arm');

  MediaArmHandler? onNext;
  MediaArmHandler? onPrevious;
  MediaDragTargetHandler? onSetDragTarget;
  MediaArmHandler? onCycleDragTarget;
  MediaVehicleHandler? onSetVehicle;
  bool _listening = false;

  void ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  Future<void> setEnabled(bool enabled) async {
    ensureListening();
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  Future<void> updatePlaybackState({
    required bool armed,
    required bool running,
    required double speedKmh,
    required String targetLabel,
    required String dragTargetName,
    required List<Map<String, String>> dragTargets,
    String? lastResult,
    int finishToken = 0,
    String finishHeadline = '',
    List<String> finishLines = const [],
    List<Map<String, dynamic>> history = const [],
    String vehicleId = '',
    String vehicleLabel = '—',
    List<Map<String, String>> vehicles = const [],
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('updateState', {
        'armed': armed,
        'running': running,
        'speedKmh': speedKmh,
        'targetLabel': targetLabel,
        'dragTargetName': dragTargetName,
        'dragTargets': dragTargets,
        if (lastResult != null) 'lastResult': lastResult,
        'finishToken': finishToken,
        'finishHeadline': finishHeadline,
        'finishLines': finishLines,
        'history': history,
        'vehicleId': vehicleId,
        'vehicleLabel': vehicleLabel,
        'vehicles': vehicles,
      });
    } catch (_) {}
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'mediaNext':
        await onNext?.call();
        return null;
      case 'mediaPrevious':
        await onPrevious?.call();
        return null;
      case 'setDragTarget':
        final args = call.arguments;
        final name = args is Map ? args['name']?.toString() : null;
        if (name != null && name.isNotEmpty) {
          await onSetDragTarget?.call(name);
        }
        return null;
      case 'cycleDragTarget':
        await onCycleDragTarget?.call();
        return null;
      case 'setVehicle':
        final args = call.arguments;
        final id = args is Map ? args['id']?.toString() : null;
        if (id != null && id.isNotEmpty) {
          await onSetVehicle?.call(id);
        }
        return null;
      default:
        throw PlatformException(
          code: 'unsupported',
          message: call.method,
        );
    }
  }
}

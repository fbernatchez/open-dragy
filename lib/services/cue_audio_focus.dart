import 'dart:io';

import 'package:flutter/services.dart';

/// Requests exclusive transient audio focus so music pauses/ducks hard during cues.
/// Linear gain > 1.0 briefly raises STREAM_MUSIC while focus is held (Android).
class CueAudioFocus {
  CueAudioFocus._();

  static const _channel = MethodChannel('opendragy/cue_audio');

  static Future<void> setGainLinear(double linear) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setCueGain', {
        'linear': linear.clamp(0.3, 1.5),
      });
    } catch (_) {}
  }

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquireFocus');
    } catch (_) {}
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('releaseFocus');
    } catch (_) {}
  }
}

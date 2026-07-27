import 'dart:io';

import 'package:flutter/services.dart';

/// Requests exclusive transient audio focus so music pauses/ducks hard during cues.
/// Does **not** change system volume.
class CueAudioFocus {
  CueAudioFocus._();

  static const _channel = MethodChannel('opendragy/cue_audio');

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

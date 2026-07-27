import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_cues.dart';
import '../models/race_metrics.dart';
import 'cue_audio_focus.dart';

/// Beep / spoken cues when drag/interval milestones are first reached.
///
/// Selected drag/interval finish is always announced when cues are on.
/// Extra intermediates are gated by [enabledOptionalIds] (see [OptionalAudioMilestone]).
///
/// Beep patterns:
/// - 1 short  — early / speed marks
/// - 2 short  — intermediate distance
/// - 1 long + 2 short — selected target / finish
class MilestoneAudioService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final Set<String> _announced = {};
  final List<_Cue> _queue = [];

  bool _enabled = true;
  AudioCueMode _mode = AudioCueMode.voice;
  double _volume = 1.0;
  bool _ready = false;
  bool _speaking = false;
  bool _disposed = false;
  bool _playedTargetFinish = false;

  /// Platform players are 0..1; >1 uses [CueAudioFocus] stream boost.
  double get _playerVolume => _volume.clamp(0.0, 1.0);

  bool get enabled => _enabled;
  AudioCueMode get mode => _mode;
  double get volume => _volume;

  Future<void> init() async {
    if (_ready || _disposed) return;
    try {
      await _beepPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceNavigationGuidance,
            // Exclusive focus: pause other media so the cue is clear at normal volume.
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
      await _beepPlayer.setReleaseMode(ReleaseMode.stop);
      await _beepPlayer.setVolume(_playerVolume);

      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(_playerVolume);
      await _tts.setPitch(1.05);
      await _tts.awaitSpeakCompletion(true);
      await _tts.setAudioAttributesForNavigation();
      await CueAudioFocus.setGainLinear(_volume);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void setVolume(double value) {
    _volume = value.clamp(0.3, 1.3);
    unawaited(_beepPlayer.setVolume(_playerVolume));
    unawaited(_tts.setVolume(_playerVolume));
    unawaited(CueAudioFocus.setGainLinear(_volume));
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _queue.clear();
      unawaited(_tts.stop());
      unawaited(_beepPlayer.stop());
      _speaking = false;
    }
  }

  void setMode(AudioCueMode mode) {
    _mode = mode;
    if (mode == AudioCueMode.beep) {
      unawaited(_tts.stop());
    }
  }

  void resetRun() {
    _announced.clear();
    _queue.clear();
    _playedTargetFinish = false;
    unawaited(_tts.stop());
    unawaited(_beepPlayer.stop());
    _speaking = false;
  }

  Future<void> _speak(String text) async {
    await CueAudioFocus.acquire();
    try {
      await _tts.setVolume(_playerVolume);
      await _tts.speak(text, focus: true);
    } finally {
      await CueAudioFocus.release();
    }
  }

  Future<void> playTestCue() async {
    if (_disposed) return;
    if (!_ready) await init();
    await _beepPlayer.setVolume(_playerVolume);
    await _tts.setVolume(_playerVolume);
    if (_mode == AudioCueMode.beep) {
      await CueAudioFocus.acquire();
      try {
        await _playPattern(_BeepPattern.finish);
      } finally {
        await CueAudioFocus.release();
      }
    } else {
      await _speak('Quarter mile');
    }
  }

  /// Helmet confirmation after Cardo / AA media ARM (plays even if run cues off).
  Future<void> announceArmed() async {
    if (_disposed) return;
    if (!_ready) await init();
    await _beepPlayer.setVolume(_playerVolume);
    await _tts.setVolume(_playerVolume);
    if (_mode == AudioCueMode.beep) {
      await CueAudioFocus.acquire();
      try {
        await _playToneForced(long: true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _playToneForced(long: false);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await _playToneForced(long: false);
      } finally {
        await CueAudioFocus.release();
      }
    } else {
      try {
        await _speak('Armed');
      } catch (_) {}
    }
  }

  Future<void> announceDisarmed() async {
    if (_disposed) return;
    if (!_ready) await init();
    await _beepPlayer.setVolume(_playerVolume);
    await _tts.setVolume(_playerVolume);
    if (_mode == AudioCueMode.beep) {
      await CueAudioFocus.acquire();
      try {
        await _playToneForced(long: false);
      } finally {
        await CueAudioFocus.release();
      }
    } else {
      try {
        await _speak('Disarmed');
      } catch (_) {}
    }
  }

  void onMetricsUpdate({
    required RaceMetrics previous,
    required RaceMetrics next,
    required bool isMetric,
    /// Milestone id for the armed drag target (`14mile`, …), or null (interval).
    String? targetMilestoneId,
    /// [OptionalAudioMilestone.id] values the user opted into.
    required Set<String> enabledOptionalIds,
  }) {
    if (!_enabled || _disposed) return;

    if (!previous.isRunning && next.isRunning) {
      resetRun();
    }

    void maybe(
      String id,
      double? before,
      double? after,
      String phrase,
      _BeepPattern pattern,
    ) {
      if (before != null || after == null) return;
      final isTarget = targetMilestoneId != null && id == targetMilestoneId;
      if (!isTarget && !_optionalAllows(id, enabledOptionalIds)) return;
      if (!_announced.add(id)) return;
      _enqueue(
        phrase,
        pattern: isTarget ? _BeepPattern.finish : pattern,
      );
      if (isTarget) _playedTargetFinish = true;
    }

    maybe(
      '60ft',
      previous.time60ft,
      next.time60ft,
      'Sixty feet',
      _BeepPattern.single,
    );
    maybe(
      '330ft',
      previous.time330ft,
      next.time330ft,
      'Three thirty',
      _BeepPattern.single,
    );
    if (isMetric) {
      maybe(
        '0-50kmh',
        previous.time0to50kmh,
        next.time0to50kmh,
        'Fifty',
        _BeepPattern.single,
      );
      maybe(
        '100kmh',
        previous.time0to100kmh,
        next.time0to100kmh,
        'One hundred',
        _BeepPattern.single,
      );
    } else {
      maybe(
        '60mph',
        previous.time0to60mph,
        next.time0to60mph,
        'Sixty',
        _BeepPattern.single,
      );
    }
    maybe(
      '18mile',
      previous.time18Mile,
      next.time18Mile,
      'Eighth mile',
      _BeepPattern.double_,
    );
    maybe(
      '1000ft',
      previous.time1000ft,
      next.time1000ft,
      'One thousand',
      _BeepPattern.double_,
    );
    maybe(
      '14mile',
      previous.time14Mile,
      next.time14Mile,
      'Quarter mile',
      _BeepPattern.double_,
    );
    maybe(
      '12mile',
      previous.time12Mile,
      next.time12Mile,
      'Half mile',
      _BeepPattern.double_,
    );

    if (previous.isRunning &&
        !next.isRunning &&
        next.history.isNotEmpty &&
        _announced.add('finish')) {
      // Always announce run end if the selected target cue did not already fire
      // (interval mode, or drag cancelled before target).
      if (!_playedTargetFinish) {
        _enqueue('Finish', pattern: _BeepPattern.finish);
      } else if (_mode == AudioCueMode.voice) {
        _enqueue('Finish', pattern: _BeepPattern.single);
      }
    }
  }

  bool _optionalAllows(String milestoneId, Set<String> enabled) {
    if (milestoneId == '100kmh' || milestoneId == '60mph') {
      return enabled.contains(OptionalAudioMilestone.speedMark.id);
    }
    return enabled.contains(milestoneId);
  }

  void _enqueue(String phrase, {required _BeepPattern pattern}) {
    _queue.add(_Cue(phrase: phrase, pattern: pattern));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_speaking || _disposed) return;
    _speaking = true;
    try {
      while (_queue.isNotEmpty && !_disposed && _enabled) {
        final cue = _queue.removeAt(0);
        if (!_ready) {
          await init();
        }
        if (_mode == AudioCueMode.beep) {
          await CueAudioFocus.acquire();
          try {
            await _playPattern(cue.pattern);
          } finally {
            await CueAudioFocus.release();
          }
        } else if (_ready && _enabled && !_disposed) {
          await _speak(cue.phrase);
        }
      }
    } finally {
      _speaking = false;
      if (_queue.isNotEmpty && _enabled && !_disposed) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _playPattern(_BeepPattern pattern) async {
    switch (pattern) {
      case _BeepPattern.single:
        await _playTone(long: false);
        break;
      case _BeepPattern.double_:
        await _playTone(long: false);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await _playTone(long: false);
        break;
      case _BeepPattern.finish:
        await _playTone(long: true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _playTone(long: false);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await _playTone(long: false);
        break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> _playTone({required bool long}) async {
    if (!_enabled || _disposed) return;
    await _playToneForced(long: long);
  }

  Future<void> _playToneForced({required bool long}) async {
    if (_disposed) return;
    final asset = long ? 'sounds/cue_beep_long.wav' : 'sounds/cue_beep.wav';
    try {
      await _beepPlayer.setVolume(_playerVolume);
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource(asset));
      await _beepPlayer.onPlayerComplete.first.timeout(
        Duration(milliseconds: long ? 500 : 350),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _beepPlayer.dispose();
    } catch (_) {}
    await CueAudioFocus.release();
  }
}

enum _BeepPattern { single, double_, finish }

class _Cue {
  final String phrase;
  final _BeepPattern pattern;
  const _Cue({required this.phrase, required this.pattern});
}

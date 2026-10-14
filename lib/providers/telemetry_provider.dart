import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/race_metrics.dart';
import '../models/ubx_nav_pvt.dart';
import '../services/audio_recording_service.dart';
import '../services/ble_service.dart';
import '../services/physics_engine.dart';
import '../services/tts_service.dart';
import 'dragy_provider.dart';

class TelemetryProvider extends ChangeNotifier {
  final BleService _bleService;
  final PhysicsEngine _physicsEngine;
  final TtsService _ttsService;
  final AudioRecordingService _audioService;
  final DragyProvider _dragyProvider;

  RaceMetrics _metrics = RaceMetrics();
  RaceMetrics get metrics => _metrics;

  bool _isArmed = false;
  bool get isArmed => _isArmed;

  int _satellites = 0;
  int get satellites => _satellites;

  double _hdop = 0.0;
  double get hdop => _hdop;

  double _altitude = 0.0;
  double get altitude => _altitude;

  double? _latitude;
  double? get latitude => _latitude;

  double? _longitude;
  double? get longitude => _longitude;

  double _launchChartOffset = 0.0;
  DateTime? _lastGpsUpdateTime;

  double _gForceAccumulator = 0.0;
  int _gForceCount = 0;

  double _gravX = 0.0;
  double _gravY = 0.0;
  double _gravZ = 1.0;
  bool _hasGravEstimate = false;

  final List<double> _recentSpeeds = [];
  List<double> get recentSpeeds => List.unmodifiable(_recentSpeeds);

  Timer? _uiTimer;
  bool _needsUiUpdate = false;

  StreamSubscription? _ubxSubscription;
  StreamSubscription? _imuSubscription;
  StreamSubscription? _connectionSubscription;

  TelemetryProvider({
    BleService? bleService,
    PhysicsEngine? physicsEngine,
    TtsService? ttsService,
    AudioRecordingService? audioService,
    required DragyProvider dragyProvider,
    bool startTimer = true,
  })  : _bleService = bleService ?? BleService(),
        _physicsEngine = physicsEngine ?? PhysicsEngine(),
        _ttsService = ttsService ?? TtsService(),
        _audioService = audioService ?? AudioRecordingService(),
        _dragyProvider = dragyProvider {
    _initStreams();
    if (startTimer) {
      _startUiTimer();
    }
  }

  void _startUiTimer() {
    _uiTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_needsUiUpdate || _metrics.isRunning) {
        notifyListeners();
        _needsUiUpdate = false;
      }
    });
  }

  void _initStreams() {
    _connectionSubscription = _bleService.connectionStateStream.listen((connected) {
      if (!connected) {
        _isArmed = false;
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
        _recentSpeeds.clear();
        _audioService.abort();
        WakelockPlus.disable();
      } else {
        WakelockPlus.enable();
      }
      _needsUiUpdate = true;
    });

    _ubxSubscription = _bleService.ubxStream.listen(_onUbxData);
    _imuSubscription = _bleService.imuStream.listen(_onImuData);
  }

  void _onUbxData(UbxNavPvt pvt) {
    if (pvt.fixType < 2) return;

    _satellites = pvt.numSV;
    _hdop = pvt.pDOP;
    _altitude = pvt.hMSL;
    _latitude = pvt.lat;
    _longitude = pvt.lon;

    _dragyProvider.triggerWeatherFetchIfNull();

    double speedKmh = pvt.gSpeed * 3.6;

    _recentSpeeds.add(speedKmh);
    if (_recentSpeeds.length > 5) {
      _recentSpeeds.removeAt(0);
    }

    final wasRunning = _metrics.isRunning;
    final activeTestsList = [...officialTests, ..._dragyProvider.customTests];
    final oldTests = _dragyProvider.enableTts && wasRunning
        ? getCompletedTests(
            _metrics,
            useNhraRules: _dragyProvider.useNhraRules,
            activeTests: activeTestsList,
          )
        : <RaceTest>[];

    double avgGForce = _gForceCount > 0
        ? _gForceAccumulator / _gForceCount
        : _metrics.gForce;
    _gForceAccumulator = 0.0;
    _gForceCount = 0;

    _metrics = _metrics.copyWith(gForce: avgGForce);

    _metrics = _physicsEngine.updateMetrics(
      _metrics,
      speedKmh,
      _altitude,
      isArmed: _isArmed,
      runMode: _dragyProvider.runMode,
      testDistance: _dragyProvider.testDistance,
      testDistanceUnit: _dragyProvider.testDistanceUnit,
      testStartSpeed: _dragyProvider.testStartSpeed,
      testEndSpeed: _dragyProvider.testEndSpeed,
      testSpeedUnit: _dragyProvider.testSpeedUnit,
      intervalStartSpeed: _dragyProvider.intervalStartSpeed,
      intervalEndSpeed: _dragyProvider.intervalEndSpeed,
      gpsTimeSeconds: pvt.iTOW / 1000.0,
      activeTests: activeTestsList,
    );
    final isRunning = _metrics.isRunning;

    if (!wasRunning && isRunning) {
      if (_dragyProvider.enableAudioRecording) {
        _launchChartOffset = _metrics.elapsedTime;
        _audioService.commitLaunch();
      }
    }

    if (_dragyProvider.enableTts && wasRunning) {
      final newTests = getCompletedTests(
        _metrics,
        useNhraRules: _dragyProvider.useNhraRules,
        activeTests: activeTestsList,
      );
      for (final test in newTests) {
        if (!_dragyProvider.isTestEnabled(test.id)) continue;
        if (!oldTests.any((t) => t.id == test.id)) {
          if (!test.enableTts ||
              test.ttsPhrase == null ||
              test.ttsPhrase!.isEmpty) {
            continue;
          }
          if (test.speedUnit != null) {
            if (_dragyProvider.isMetric && test.speedUnit != SpeedUnit.kmh) {
              continue;
            }
            if (!_dragyProvider.isMetric && test.speedUnit != SpeedUnit.mph) {
              continue;
            }
          }
          _ttsService.speak(test.ttsPhrase!);
        }
      }
    }

    if (isRunning) {
      _lastGpsUpdateTime = DateTime.now();
    } else {
      _lastGpsUpdateTime = null;
      if (wasRunning) {
        _isArmed = false;
      }
    }

    if (wasRunning && !isRunning && _metrics.history.isNotEmpty) {
      final metricsToSave = _metrics;
      if (_dragyProvider.enableAudioRecording) {
        _audioService.stopAndSaveRun().then((audioData) {
          _dragyProvider.saveRun(
            metricsToSave,
            audioFilePath: audioData?['path'] as String?,
            audioStartOffset: (audioData?['offset'] as double?) != null
                ? (audioData!['offset'] as double) - _launchChartOffset
                : null,
          );
        });
      } else {
        _dragyProvider.saveRun(metricsToSave);
      }
    }

    _needsUiUpdate = true;
  }

  void _onImuData(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length >= 3) {
        final rawX = int.parse(parts[0].trim());
        final rawY = int.parse(parts[1].trim());
        final rawZ = int.parse(parts[2].trim());

        final double gx = rawX / 16384.0;
        final double gy = rawY / 16384.0;
        final double gz = rawZ / 16384.0;

        if (!_metrics.isRunning && isSpeedConstant) {
          const double alpha = 0.02;
          if (!_hasGravEstimate) {
            _gravX = gx;
            _gravY = gy;
            _gravZ = gz;
            _hasGravEstimate = true;
          } else {
            _gravX = _gravX * (1.0 - alpha) + gx * alpha;
            _gravY = _gravY * (1.0 - alpha) + gy * alpha;
            _gravZ = _gravZ * (1.0 - alpha) + gz * alpha;
          }
        }

        final double gForce = computeLeveledGForce(
          boxPivotAngle: _dragyProvider.boxPivotAngle,
          gx: gx,
          gy: gy,
          gz: gz,
          gravX: _gravX,
          gravY: _gravY,
          gravZ: _gravZ,
        );

        double calibratedGForce = gForce;
        if (calibratedGForce.abs() < 0.05) {
          calibratedGForce = 0.0;
        }

        _gForceAccumulator += calibratedGForce;
        _gForceCount++;

        _metrics = _metrics.copyWith(gForce: calibratedGForce);
        _needsUiUpdate = true;
      }
    } catch (_) {}
  }

  bool get isSpeedConstant {
    if (_metrics.speedKmh == 0.0) return true;
    if (_recentSpeeds.length < 4) return false;
    double minSpeed = _recentSpeeds[0];
    double maxSpeed = _recentSpeeds[0];
    for (int i = 1; i < _recentSpeeds.length; i++) {
      if (_recentSpeeds[i] < minSpeed) minSpeed = _recentSpeeds[i];
      if (_recentSpeeds[i] > maxSpeed) maxSpeed = _recentSpeeds[i];
    }
    return (maxSpeed - minSpeed) < 0.2;
  }

  double get liveElapsedTime {
    double baseTime = _metrics.elapsedTime;
    if (_metrics.isRunning && _lastGpsUpdateTime != null) {
      final delta =
          DateTime.now().difference(_lastGpsUpdateTime!).inMicroseconds /
          1000000.0;
      final clampedDelta = delta.clamp(0.0, _physicsEngine.lastValidDt);
      baseTime += clampedDelta;
    }

    final isStandingStart = _dragyProvider.runMode == RunMode.drag ||
        (_dragyProvider.runMode == RunMode.interval &&
            _dragyProvider.testStartSpeed == 0.0);

    if (_dragyProvider.useNhraRules && isStandingStart) {
      if (_metrics.rolloutTime1ft != null) {
        return max(0.0, baseTime - _metrics.rolloutTime1ft!);
      } else {
        return 0.0;
      }
    }

    return baseTime;
  }

  void toggleArm() {
    if (_metrics.isRunning) {
      _isArmed = false;
      _audioService.abort();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
    } else {
      _isArmed = !_isArmed;
      if (_isArmed) {
        _metrics = _physicsEngine.reset().copyWith(speedKmh: _metrics.speedKmh);
        _lastGpsUpdateTime = null;
        if (_dragyProvider.enableAudioRecording) {
          _audioService.startArmedBuffer();
        }
      } else {
        _audioService.abort();
      }
    }
    _needsUiUpdate = true;
    notifyListeners();
  }

  void arm() {
    if (!_isArmed) toggleArm();
  }

  void disarm() {
    if (_isArmed) toggleArm();
  }

  void resetRace() {
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    _needsUiUpdate = true;
    notifyListeners();
  }

  // Unit tests or manual test state injection
  void setMetricsForTest(RaceMetrics metrics) {
    _metrics = metrics;
    notifyListeners();
  }

  void setArmedForTest(bool armed) {
    _isArmed = armed;
    notifyListeners();
  }

  void setSatellitesAndHdopForTest(int satellites, double hdop) {
    _satellites = satellites;
    _hdop = hdop;
    notifyListeners();
  }

  static double computeLeveledGForce({
    required int boxPivotAngle,
    required double gx,
    required double gy,
    required double gz,
    double gravX = 0.0,
    double gravY = 0.0,
    double gravZ = 1.0,
  }) {
    final gravNorm = sqrt(gravX * gravX + gravY * gravY + gravZ * gravZ);
    final double ux;
    final double uy;
    final double uz;
    if (gravNorm > 0.001) {
      ux = gravX / gravNorm;
      uy = gravY / gravNorm;
      uz = gravZ / gravNorm;
    } else {
      ux = 0.0;
      uy = 0.0;
      uz = 1.0;
    }

    final rad = boxPivotAngle * (pi / 180.0);
    final bx = -sin(rad);
    final by = cos(rad);
    const bz = 0.0;

    final dot = bx * ux + by * uy + bz * uz;
    final double px = bx - dot * ux;
    final double py = by - dot * uy;
    final double pz = bz - dot * uz;

    final double pLen = sqrt(px * px + py * py + pz * pz);

    final double fx;
    final double fy;
    final double fz;
    if (pLen > 0.001) {
      fx = px / pLen;
      fy = py / pLen;
      fz = pz / pLen;
    } else {
      fx = bx;
      fy = by;
      fz = bz;
    }

    return gx * fx + gy * fy + gz * fz;
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _uiTimer?.cancel();
    _uiTimer = null;
    _ubxSubscription?.cancel();
    _imuSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}

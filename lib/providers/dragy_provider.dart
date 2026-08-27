import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/race_metrics.dart';
import '../models/saved_run.dart';
import '../models/vehicle.dart';
import '../services/ble_service.dart';
import '../services/physics_engine.dart';
import '../services/history_service.dart';
import '../services/garage_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../utils/unit_converter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/race_target.dart';
import '../services/tts_service.dart';
import '../services/audio_recording_service.dart';
import 'dart:io';

enum RaceDragTarget {
  sixtyFeet('60ft'),
  threeHundredThirtyFeet('330ft'),
  eighthMile('1/8 mile'),
  thousandFeet('1000ft'),
  quarterMile('1/4 mile'),
  halfMile('1/2 mile');

  final String label;
  const RaceDragTarget(this.label);
}

enum RaceIntervalTarget {
  zeroToSixtyMph('0-60 mph', '0-60mph'),
  zeroToOneHundredMph('0-100 mph', 'custom_0_100_mph'),
  fiftyToSeventyFiveMph('50-75 mph', 'custom_50_75_mph'),
  sixtyToOneHundredMph('60-100 mph', 'custom_60_100_mph'),
  sixtyToOneThirtyMph('60-130 mph', '60-130mph'),
  zeroToOneThirtyMph('0-130 mph', '0-130mph'),
  zeroToOneHundredKmh('0-100 km/h', '0-100kmh'),
  zeroToOneSixtyKmh('0-160 km/h', 'custom_0_160_kmh'),
  eightyToOneTwentyKmh('80-120 km/h', 'custom_80_120_kmh'),
  oneHundredToOneSixtyKmh('100-160 km/h', 'custom_100_160_kmh'),
  oneHundredToTwoHundredKmh('100-200 km/h', '100-200kmh'),
  zeroToTwoHundredKmh('0-200 km/h', '0-200kmh'),
  custom('Custom Range...', 'custom');

  final String label;
  final String id;
  const RaceIntervalTarget(this.label, this.id);
}

class DragyProvider extends ChangeNotifier {
  final BleService _bleService = BleService();
  final PhysicsEngine _physicsEngine = PhysicsEngine();
  final HistoryService _historyService = HistoryService();
  final GarageService _garageService = GarageService();
  final SettingsService _settingsService = SettingsService();
  final WeatherService _weatherService = WeatherService();
  final TtsService _ttsService = TtsService();
  final AudioRecordingService _audioService = AudioRecordingService();

  double? _latitude;
  double? get latitude => _latitude;

  double? _longitude;
  double? get longitude => _longitude;

  double? _currentTemperature;
  double? get currentTemperature => _currentTemperature;

  double? _currentHumidity;
  double? get currentHumidity => _currentHumidity;

  int? _currentWeatherCode;
  int? get currentWeatherCode => _currentWeatherCode;

  Timer? _weatherTimer;
  bool _isFetchingWeather = false;

  RaceMetrics _metrics = RaceMetrics();
  RaceMetrics get metrics => _metrics;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  int _satellites = 0;
  int get satellites => _satellites;

  double _hdop = 0.0;
  double get hdop => _hdop;

  double _altitude = 0.0;
  double get altitude => _altitude;

  bool _isMetric = false;
  bool get isMetric => _isMetric;

  RaceDragTarget _activeDragTarget = RaceDragTarget.quarterMile;
  RaceDragTarget get activeDragTarget => _activeDragTarget;

  // --- Settings ---
  bool _tempInCelsius = true;
  bool get tempInCelsius => _tempInCelsius;

  bool _useNhraRules = true;
  bool get useNhraRules => _useNhraRules;

  bool _enableTts = true;
  bool get enableTts => _enableTts;

  bool _enableAudioRecording = true;
  bool get enableAudioRecording => _enableAudioRecording;

  // --- Arming & Run Modes ---
  bool _isArmed = false;
  bool get isArmed => _isArmed;

  String _runMode = 'drag';
  String get runMode => _runMode;

  double _launchChartOffset = 0.0;

  RaceIntervalTarget _activeIntervalTarget =
      RaceIntervalTarget.sixtyToOneThirtyMph;
  RaceIntervalTarget get activeIntervalTarget => _activeIntervalTarget;

  double _customIntervalStartSpeed = 100.0;
  double get customIntervalStartSpeed => _customIntervalStartSpeed;

  double _customIntervalEndSpeed = 200.0;
  double get customIntervalEndSpeed => _customIntervalEndSpeed;

  double get intervalStartSpeed {
    switch (_activeIntervalTarget) {
      case RaceIntervalTarget.zeroToSixtyMph:
        return 0.0;
      case RaceIntervalTarget.zeroToOneHundredMph:
        return 0.0;
      case RaceIntervalTarget.fiftyToSeventyFiveMph:
        return 80.4672;
      case RaceIntervalTarget.sixtyToOneHundredMph:
        return 96.5606;
      case RaceIntervalTarget.sixtyToOneThirtyMph:
        return 96.5606;
      case RaceIntervalTarget.zeroToOneThirtyMph:
        return 0.0;
      case RaceIntervalTarget.zeroToOneHundredKmh:
        return 0.0;
      case RaceIntervalTarget.zeroToOneSixtyKmh:
        return 0.0;
      case RaceIntervalTarget.eightyToOneTwentyKmh:
        return 80.0;
      case RaceIntervalTarget.oneHundredToOneSixtyKmh:
        return 100.0;
      case RaceIntervalTarget.oneHundredToTwoHundredKmh:
        return 100.0;
      case RaceIntervalTarget.zeroToTwoHundredKmh:
        return 0.0;
      case RaceIntervalTarget.custom:
        return _isMetric
            ? _customIntervalStartSpeed
            : UnitConverter.mphToKmh(_customIntervalStartSpeed);
    }
  }

  double get intervalEndSpeed {
    switch (_activeIntervalTarget) {
      case RaceIntervalTarget.zeroToSixtyMph:
        return 96.5606;
      case RaceIntervalTarget.zeroToOneHundredMph:
        return 160.9344;
      case RaceIntervalTarget.fiftyToSeventyFiveMph:
        return 120.7008;
      case RaceIntervalTarget.sixtyToOneHundredMph:
        return 160.9344;
      case RaceIntervalTarget.sixtyToOneThirtyMph:
        return 209.2147;
      case RaceIntervalTarget.zeroToOneThirtyMph:
        return 209.2147;
      case RaceIntervalTarget.zeroToOneHundredKmh:
        return 100.0;
      case RaceIntervalTarget.zeroToOneSixtyKmh:
        return 160.0;
      case RaceIntervalTarget.eightyToOneTwentyKmh:
        return 120.0;
      case RaceIntervalTarget.oneHundredToOneSixtyKmh:
        return 160.0;
      case RaceIntervalTarget.oneHundredToTwoHundredKmh:
        return 200.0;
      case RaceIntervalTarget.zeroToTwoHundredKmh:
        return 200.0;
      case RaceIntervalTarget.custom:
        return _isMetric
            ? _customIntervalEndSpeed
            : UnitConverter.mphToKmh(_customIntervalEndSpeed);
    }
  }

  double get customIntervalStartSpeedUserUnit {
    return _customIntervalStartSpeed;
  }

  double get customIntervalEndSpeedUserUnit {
    return _customIntervalEndSpeed;
  }

  String get activeDragTargetLabel {
    return _activeDragTarget.label;
  }

  String get activeIntervalTargetLabel {
    if (_activeIntervalTarget == RaceIntervalTarget.custom) {
      final start = _customIntervalStartSpeed.round();
      final end = _customIntervalEndSpeed.round();
      final unit = _isMetric ? 'km/h' : 'mph';
      return '$start-$end $unit';
    } else {
      return _activeIntervalTarget.label;
    }
  }

  double? get targetDistance {
    if (_runMode != 'drag') return null;
    switch (_activeDragTarget) {
      case RaceDragTarget.sixtyFeet:
        return 60.0;
      case RaceDragTarget.threeHundredThirtyFeet:
        return 330.0;
      case RaceDragTarget.eighthMile:
        return 0.125;
      case RaceDragTarget.thousandFeet:
        return 1000.0;
      case RaceDragTarget.quarterMile:
        return 0.25;
      case RaceDragTarget.halfMile:
        return 0.5;
    }
  }

  String? get targetDistanceUnit {
    if (_runMode != 'drag') return null;
    switch (_activeDragTarget) {
      case RaceDragTarget.sixtyFeet:
        return 'feet';
      case RaceDragTarget.threeHundredThirtyFeet:
        return 'feet';
      case RaceDragTarget.eighthMile:
        return 'mile';
      case RaceDragTarget.thousandFeet:
        return 'feet';
      case RaceDragTarget.quarterMile:
        return 'mile';
      case RaceDragTarget.halfMile:
        return 'mile';
    }
  }

  double? get targetStartSpeed {
    if (_runMode == 'interval') {
      return intervalStartSpeed;
    }
    return null;
  }

  double? get targetEndSpeed {
    if (_runMode == 'interval') {
      return intervalEndSpeed;
    }
    return null;
  }

  String? get targetSpeedUnit {
    if (_runMode != 'interval') return null;
    if (_activeIntervalTarget == RaceIntervalTarget.custom) {
      return _isMetric ? 'kmh' : 'mph';
    }
    switch (_activeIntervalTarget) {
      case RaceIntervalTarget.zeroToSixtyMph:
      case RaceIntervalTarget.zeroToOneHundredMph:
      case RaceIntervalTarget.fiftyToSeventyFiveMph:
      case RaceIntervalTarget.sixtyToOneHundredMph:
      case RaceIntervalTarget.sixtyToOneThirtyMph:
      case RaceIntervalTarget.zeroToOneThirtyMph:
        return 'mph';
      case RaceIntervalTarget.zeroToOneHundredKmh:
      case RaceIntervalTarget.zeroToOneSixtyKmh:
      case RaceIntervalTarget.eightyToOneTwentyKmh:
      case RaceIntervalTarget.oneHundredToOneSixtyKmh:
      case RaceIntervalTarget.oneHundredToTwoHundredKmh:
      case RaceIntervalTarget.zeroToTwoHundredKmh:
        return 'kmh';
      default:
        return _isMetric ? 'kmh' : 'mph';
    }
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

  // --- Garage ---
  List<Vehicle> _vehicles = [];
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);

  String? _activeVehicleId;
  String? get activeVehicleId => _activeVehicleId;

  Vehicle? get activeVehicle {
    if (_activeVehicleId == null) return null;
    try {
      return _vehicles.firstWhere((v) => v.id == _activeVehicleId);
    } catch (_) {
      return null;
    }
  }

  double _gForceCalibrationOffset = 0.0;
  DateTime? _lastGpsUpdateTime;

  double get liveElapsedTime {
    double baseTime = _metrics.elapsedTime;
    if (_metrics.isRunning && _lastGpsUpdateTime != null) {
      final delta =
          DateTime.now().difference(_lastGpsUpdateTime!).inMicroseconds /
          1000000.0;
      final clampedDelta = delta.clamp(0.0, _physicsEngine.lastValidDt);
      baseTime += clampedDelta;
    }

    if (_useNhraRules && (_runMode == 'drag' || targetStartSpeed == 0.0)) {
      if (_metrics.rolloutTime1ft != null) {
        return max(0.0, baseTime - _metrics.rolloutTime1ft!);
      } else {
        return 0.0;
      }
    }

    return baseTime;
  }

  StreamSubscription? _ubxSubscription;
  StreamSubscription? _imuSubscription;
  StreamSubscription? _connectionSubscription;

  final List<double> _recentSpeeds = [];

  List<SavedRun> _savedRuns = [];
  List<SavedRun> get savedRuns => _savedRuns;

  Timer? _uiTimer;
  bool _needsUiUpdate = false;

  String _appVersion = '';
  String get appVersion => _appVersion;

  String _firmwareVersion = '';
  String get firmwareVersion => _firmwareVersion;

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      _needsUiUpdate = true;
    } catch (_) {}
  }

  DragyProvider() {
    loadSavedRuns();
    _loadGarage();
    _loadSettings();
    _loadAppVersion();
    _startWeatherTimer();

    _uiTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_needsUiUpdate || _metrics.isRunning) {
        notifyListeners();
        _needsUiUpdate = false;
      }
    });

    _connectionSubscription = _bleService.connectionStateStream.listen((
      connected,
    ) {
      _isConnected = connected;
      if (!connected) {
        _connectedDevice = null;
        _firmwareVersion = '';
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

    _bleService.firmwareVersionStream.listen((version) {
      _firmwareVersion = version;
      _needsUiUpdate = true;
    });

    _ubxSubscription = _bleService.ubxStream.listen((pvt) {
      bool updated = false;

      if (pvt.fixType >= 2) { // 2 = 2D fix, 3 = 3D fix
        _satellites = pvt.numSV;
        _hdop = pvt.pDOP;
        _altitude = pvt.hMSL;
        _latitude = pvt.lat;
        _longitude = pvt.lon;
        _triggerWeatherFetchIfNull();

        double speedKmh = pvt.gSpeed * 3.6; // m/s to km/h

        _recentSpeeds.add(speedKmh);
        if (_recentSpeeds.length > 5) {
          _recentSpeeds.removeAt(0);
        }

        final wasRunning = _metrics.isRunning;
        final oldTests = _enableTts && wasRunning
            ? getCompletedTests(_metrics, useNhraRules: _useNhraRules)
            : <OfficialTest>[];

        _metrics = _physicsEngine.updateMetrics(
          _metrics,
          speedKmh,
          _altitude,
          isArmed: _isArmed,
          runMode: _runMode,
          targetDistance: targetDistance,
          targetDistanceUnit: targetDistanceUnit,
          targetStartSpeed: targetStartSpeed,
          targetEndSpeed: targetEndSpeed,
          targetSpeedUnit: targetSpeedUnit,
          intervalStartSpeed: intervalStartSpeed,
          intervalEndSpeed: intervalEndSpeed,
          gpsTimeSeconds: pvt.iTOW / 1000.0,
        );
        final isRunning = _metrics.isRunning;

        if (!wasRunning && isRunning) {
          if (_enableAudioRecording) {
            _launchChartOffset = _metrics.elapsedTime;
            _audioService.commitLaunch();
          }
          if (_enableTts) {
            // Silently wake up the TTS engine at launch so it loads the voice models
            // into RAM. This eliminates the ~1s latency for the first actual milestone.
            _ttsService.speak(" ");
          }
        }

        if (_enableTts && wasRunning) {
          final newTests = getCompletedTests(
            _metrics,
            useNhraRules: _useNhraRules,
          );
          for (final test in newTests) {
            if (!oldTests.any((t) => t.id == test.id)) {
              if (!test.enableTts ||
                  test.ttsPhrase == null ||
                  test.ttsPhrase!.isEmpty)
                continue;
              if (test.speedUnit != null) {
                if (_isMetric && test.speedUnit != SpeedUnit.kmh) continue;
                if (!_isMetric && test.speedUnit != SpeedUnit.mph) continue;
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
            _isArmed = false; // Auto-disarm on completion
          }
        }

        // Check if run just finished
        if (wasRunning && !isRunning && _metrics.history.isNotEmpty) {
          final metricsToSave = _metrics;
          
          if (_enableAudioRecording) {
            _audioService.stopAndSaveRun().then((audioData) {
              _saveRunToHistory(
                metricsToSave,
                audioFilePath: audioData?['path'] as String?,
                audioStartOffset: (audioData?['offset'] as double?) != null
                    ? (audioData!['offset'] as double) - _launchChartOffset
                    : null,
              );
            });
          } else {
            _saveRunToHistory(metricsToSave);
          }
        }

        updated = true;
      }

      if (updated) {
        _needsUiUpdate = true;
      }
    });

    _imuSubscription = _bleService.imuStream.listen((csv) {
      try {
        final parts = csv.split(',');
        if (parts.length >= 3) {
          // Assuming BMI160 format: "X,Y,Z" raw integers
          // We'll use the Y axis for longitudinal G-force (front to back) after a 90-degree pivot
          int y = int.parse(parts[1].trim());

          // 16384 LSB/g is standard for +/- 2G range on BMI160
          double gForce = y / 16384.0;

          // Automatic progressive calibration when speed is constant (cruising or stationary) and not in an active run
          if (!_metrics.isRunning && isSpeedConstant) {
            const double alpha = 0.02; // Calibration speed factor (EMA)
            _gForceCalibrationOffset =
                _gForceCalibrationOffset * (1.0 - alpha) + gForce * alpha;
          }

          double calibratedGForce = gForce - _gForceCalibrationOffset;

          // Clamp noise to prevent "-0.0" from showing up
          if (calibratedGForce.abs() < 0.05) {
            calibratedGForce = 0.0;
          }

          _metrics = _metrics.copyWith(gForce: calibratedGForce);
          _needsUiUpdate = true;
        }
      } catch (e) {
        // Ignore parsing errors for individual frames
      }
    });
  }

  BleService get bleService => _bleService;

  Future<bool> connect(BluetoothDevice device) async {
    final success = await _bleService.connectToDevice(device);
    if (success) {
      _connectedDevice = device;
      notifyListeners();
    }
    return success;
  }

  Future<void> disconnect() async {
    try {
      await _bleService.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    notifyListeners();
  }

  void resetRace() {
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    notifyListeners();
  }

  // --- Local History Methods ---

  Future<void> loadSavedRuns() async {
    _savedRuns = await _historyService.loadRuns();
    notifyListeners();
  }

  Future<void> _saveRunToHistory(
    RaceMetrics runMetrics, {
    String? audioFilePath,
    double? audioStartOffset,
  }) async {
    // Filter out creeping / GPS wander blips
    if (runMetrics.isValidRun) {
      final vehicle = activeVehicle;
      final runId = DateTime.now().millisecondsSinceEpoch.toString();

      final savedRun = SavedRun(
        id: runId,
        dateTime: DateTime.now(),
        metrics: runMetrics,
        temperature: _currentTemperature,
        humidity: _currentHumidity,
        vehicleId: vehicle?.id,
        vehicleName: vehicle?.displayName,
        audioFilePath: audioFilePath,
        audioStartOffset: audioStartOffset,
      );

      // Save run locally and show in UI immediately
      await _historyService.saveRun(savedRun);
      _savedRuns.insert(0, savedRun);
      _needsUiUpdate = true;
      notifyListeners();

      // Fetch weather asynchronously in the background if coordinates are available
      final lat = _latitude;
      final lon = _longitude;
      if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
        _fetchAndApplyWeather(runId, lat, lon);
      }
    } else {
      // Run was rejected. Discard the audio file if it was created.
      if (audioFilePath != null) {
        try {
          File(audioFilePath).deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _fetchAndApplyWeather(
    String runId,
    double lat,
    double lon,
  ) async {
    final weather = await _weatherService.fetchWeather(lat, lon);
    if (weather != null) {
      final temp = weather['temp']!;
      final humid = weather['humid']!;

      final index = _savedRuns.indexWhere((r) => r.id == runId);
      if (index != -1) {
        // Copy-with the fetched weather data while preserving other fields (like notes user might have typed in the meantime)
        final updatedRun = _savedRuns[index].copyWith(
          temperature: temp,
          humidity: humid,
        );
        _savedRuns[index] = updatedRun;
        await _historyService.updateRun(updatedRun);
        _needsUiUpdate = true;
        notifyListeners();
      }
    }
  }

  Future<void> deleteRun(String id) async {
    final index = _savedRuns.indexWhere((r) => r.id == id);
    if (index != -1) {
      final run = _savedRuns[index];
      if (run.audioFilePath != null) {
        try {
          final file = File(run.audioFilePath!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    await _historyService.deleteRun(id);
    _savedRuns.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  Future<void> updateRunNotes(String id, String notes) async {
    final index = _savedRuns.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedRun = _savedRuns[index].copyWith(notes: notes);
      _savedRuns[index] = updatedRun;
      await _historyService.updateRun(updatedRun);
      notifyListeners();
    }
  }

  Future<void> updateRunVehicle(
    String id,
    String? vehicleId,
    String? vehicleName,
  ) async {
    final index = _savedRuns.indexWhere((r) => r.id == id);
    if (index != -1) {
      final old = _savedRuns[index];
      final updatedRun = SavedRun(
        id: old.id,
        dateTime: old.dateTime,
        metrics: old.metrics,
        notes: old.notes,
        temperature: old.temperature,
        humidity: old.humidity,
        vehicleId: vehicleId,
        vehicleName: vehicleName,
      );
      _savedRuns[index] = updatedRun;
      await _historyService.updateRun(updatedRun);
      notifyListeners();
    }
  }

  void toggleSpeedUnit() {
    _isMetric = !_isMetric;
    _syncActiveTargetToUnit();
    if (_isMetric) {
      _customIntervalStartSpeed = UnitConverter.mphToKmh(
        _customIntervalStartSpeed,
      ).roundToDouble();
      _customIntervalEndSpeed = UnitConverter.mphToKmh(
        _customIntervalEndSpeed,
      ).roundToDouble();
    } else {
      _customIntervalStartSpeed = UnitConverter.kmhToMph(
        _customIntervalStartSpeed,
      ).roundToDouble();
      _customIntervalEndSpeed = UnitConverter.kmhToMph(
        _customIntervalEndSpeed,
      ).roundToDouble();
    }
    _saveSettings();
    notifyListeners();
  }

  void setActiveDragTarget(RaceDragTarget target) {
    if (_activeDragTarget != target) {
      _activeDragTarget = target;
      _isArmed = false; // Disarm on target change
      _audioService.abort();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      _saveSettings();
      notifyListeners();
    }
  }

  // --- Settings Methods ---

  void setMetric(bool isMetric) {
    if (_isMetric != isMetric) {
      _isMetric = isMetric;
      _syncActiveTargetToUnit();
      if (_isMetric) {
        _customIntervalStartSpeed = UnitConverter.mphToKmh(
          _customIntervalStartSpeed,
        ).roundToDouble();
        _customIntervalEndSpeed = UnitConverter.mphToKmh(
          _customIntervalEndSpeed,
        ).roundToDouble();
      } else {
        _customIntervalStartSpeed = UnitConverter.kmhToMph(
          _customIntervalStartSpeed,
        ).roundToDouble();
        _customIntervalEndSpeed = UnitConverter.kmhToMph(
          _customIntervalEndSpeed,
        ).roundToDouble();
      }
      _saveSettings();
      notifyListeners();
    }
  }

  void _syncActiveTargetToUnit() {
    if (_isMetric) {
      if (_activeIntervalTarget == RaceIntervalTarget.sixtyToOneThirtyMph) {
        _activeIntervalTarget = RaceIntervalTarget.oneHundredToTwoHundredKmh;
      } else if (_activeIntervalTarget == RaceIntervalTarget.zeroToSixtyMph) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToOneHundredKmh;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.fiftyToSeventyFiveMph) {
        _activeIntervalTarget = RaceIntervalTarget.eightyToOneTwentyKmh;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.zeroToOneThirtyMph) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToTwoHundredKmh;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.sixtyToOneHundredMph) {
        _activeIntervalTarget = RaceIntervalTarget.oneHundredToOneSixtyKmh;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.zeroToOneHundredMph) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToOneSixtyKmh;
      }
    } else {
      if (_activeIntervalTarget ==
          RaceIntervalTarget.oneHundredToTwoHundredKmh) {
        _activeIntervalTarget = RaceIntervalTarget.sixtyToOneThirtyMph;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.zeroToOneHundredKmh) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToSixtyMph;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.eightyToOneTwentyKmh) {
        _activeIntervalTarget = RaceIntervalTarget.fiftyToSeventyFiveMph;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.zeroToTwoHundredKmh) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToOneThirtyMph;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.oneHundredToOneSixtyKmh) {
        _activeIntervalTarget = RaceIntervalTarget.sixtyToOneHundredMph;
      } else if (_activeIntervalTarget ==
          RaceIntervalTarget.zeroToOneSixtyKmh) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToOneHundredMph;
      }
    }
  }

  void setTempInCelsius(bool value) {
    _tempInCelsius = value;
    _saveSettings();
    notifyListeners();
  }

  void setUseNhraRules(bool value) {
    if (_useNhraRules != value) {
      _useNhraRules = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void setEnableTts(bool value) {
    if (_enableTts != value) {
      _enableTts = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void setEnableAudioRecording(bool value) {
    if (_enableAudioRecording != value) {
      _enableAudioRecording = value;
      if (!_enableAudioRecording) {
        _audioService.abort();
      } else if (_isArmed && !_metrics.isRunning) {
        _audioService.startArmedBuffer();
      }
      _saveSettings();
      notifyListeners();
    }
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
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
        if (_enableAudioRecording) {
          _audioService.startArmedBuffer();
        }
      } else {
        _audioService.abort();
      }
    }
    notifyListeners();
  }

  void setRunMode(String mode) {
    if (_runMode != mode) {
      _runMode = mode;
      _isArmed = false; // Disarm on mode change
      _audioService.abort();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      _saveSettings();
      notifyListeners();
    }
  }

  void setActiveIntervalTarget(RaceIntervalTarget target) {
    if (_activeIntervalTarget != target) {
      _activeIntervalTarget = target;
      _isArmed = false; // Disarm on target change
      _audioService.abort();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      _saveSettings();
      notifyListeners();
    }
  }

  void setCustomIntervalRange(double start, double end) {
    _customIntervalStartSpeed = start.roundToDouble();
    _customIntervalEndSpeed = end.roundToDouble();
    _isArmed = false; // Disarm on range change
    _audioService.abort();
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final data = await _settingsService.load();
    _isMetric = data['isMetric'] as bool? ?? false;
    _tempInCelsius = data['tempInCelsius'] as bool? ?? true;
    _useNhraRules = data['useNhraRules'] as bool? ?? true;
    _enableTts = data['enableTts'] as bool? ?? true;
    _enableAudioRecording = data['enableAudioRecording'] as bool? ?? true;
    _runMode = data['runMode'] as String? ?? 'drag';

    final dragTargetName = data['activeDragTarget'] as String?;
    _activeDragTarget = RaceDragTarget.values.firstWhere(
      (e) => e.name == dragTargetName,
      orElse: () => RaceDragTarget.quarterMile,
    );

    final intervalTargetName = data['activeIntervalTarget'] as String?;
    _activeIntervalTarget = RaceIntervalTarget.values.firstWhere(
      (e) => e.name == intervalTargetName,
      orElse: () => RaceIntervalTarget.sixtyToOneThirtyMph,
    );

    _customIntervalStartSpeed =
        (data['customIntervalStartSpeed'] as num?)?.toDouble() ?? 100.0;
    _customIntervalEndSpeed =
        (data['customIntervalEndSpeed'] as num?)?.toDouble() ?? 200.0;
    _syncActiveTargetToUnit();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _settingsService.save({
      'isMetric': _isMetric,
      'tempInCelsius': _tempInCelsius,
      'useNhraRules': _useNhraRules,
      'enableTts': _enableTts,
      'enableAudioRecording': _enableAudioRecording,
      'runMode': _runMode,
      'activeDragTarget': _activeDragTarget.name,
      'activeIntervalTarget': _activeIntervalTarget.name,
      'customIntervalStartSpeed': _customIntervalStartSpeed.round(),
      'customIntervalEndSpeed': _customIntervalEndSpeed.round(),
    });
  }

  // --- Garage Methods ---

  Future<void> _loadGarage() async {
    _vehicles = await _garageService.loadVehicles();
    _activeVehicleId = await _garageService.loadActiveVehicleId();
    notifyListeners();
  }

  Future<void> _saveGarage() async {
    await _garageService.save(_vehicles, _activeVehicleId);
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    _vehicles.add(vehicle);
    // Auto-select if first vehicle
    if (_vehicles.length == 1) {
      _activeVehicleId = vehicle.id;
    }
    await _saveGarage();
    notifyListeners();
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index != -1) {
      _vehicles[index] = vehicle;
      await _saveGarage();
      notifyListeners();
    }
  }

  Future<void> deleteVehicle(String id) async {
    _vehicles.removeWhere((v) => v.id == id);
    if (_activeVehicleId == id) {
      _activeVehicleId = _vehicles.isNotEmpty ? _vehicles.first.id : null;
    }
    await _saveGarage();
    notifyListeners();
  }

  Future<void> setActiveVehicle(String id) async {
    _activeVehicleId = id;
    await _saveGarage();
    notifyListeners();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _ubxSubscription?.cancel();
    _imuSubscription?.cancel();
    _connectionSubscription?.cancel();
    WakelockPlus.disable();
    _weatherTimer?.cancel();
    super.dispose();
  }

  void _startWeatherTimer() {
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchCurrentWeather();
    });
    // Trigger immediately
    _triggerWeatherFetchIfNull();
  }

  void _triggerWeatherFetchIfNull() {
    if (_currentTemperature == null && !_isFetchingWeather) {
      _fetchCurrentWeather();
    }
  }

  Future<void> _fetchCurrentWeather() async {
    final lat = _latitude;
    final lon = _longitude;
    if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
      if (_isFetchingWeather) return;
      _isFetchingWeather = true;
      try {
        final weather = await _weatherService.fetchWeather(lat, lon);
        if (weather != null) {
          _currentTemperature = weather['temp'];
          _currentHumidity = weather['humid'];
          _currentWeatherCode = weather['weatherCode']?.toInt();
          _needsUiUpdate = true;
        }
      } finally {
        _isFetchingWeather = false;
      }
    }
  }
}

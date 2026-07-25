import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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
import '../services/pocket_foreground_service.dart';
import '../services/ride_recorder.dart';
import '../utils/nmea_parser.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  final RideRecorder _rideRecorder = RideRecorder();

  double? _latitude;
  double? get latitude => _latitude;

  double? _longitude;
  double? get longitude => _longitude;

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

  /// When true: screen may turn off; FGS keeps timing alive (pocket / motorcycle).
  /// When false: keep display awake while connected (classic dash use).
  bool _pocketMode = false;
  bool get pocketMode => _pocketMode;

  // --- Logger mode (continuous raw → PC) ---
  bool _isLoggerMode = false;
  bool get isLoggerMode => _isLoggerMode;

  bool _isRideRecording = false;
  bool get isRideRecording => _isRideRecording;

  int get rideTrackPointCount => _rideRecorder.trackPointCount;
  int get rideGpsRowCount => _rideRecorder.gpsRowCount;

  String? _loggerProject;
  String? get loggerProject => _loggerProject;

  String _loggerConfiguration = '';
  String get loggerConfiguration => _loggerConfiguration;

  String? _bleReconnectId;
  Timer? _reconnectTimer;

  // --- Arming & Run Modes ---
  bool _isArmed = false;
  bool get isArmed => _isArmed;

  String _runMode = 'drag';
  String get runMode => _runMode;

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
            : _customIntervalStartSpeed / 0.621371;
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
            : _customIntervalEndSpeed / 0.621371;
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

  StreamSubscription? _nmeaSubscription;
  StreamSubscription? _imuSubscription;
  StreamSubscription? _connectionSubscription;

  final List<double> _recentSpeeds = [];

  List<SavedRun> _savedRuns = [];
  List<SavedRun> get savedRuns => _savedRuns;

  Timer? _uiTimer;
  bool _needsUiUpdate = false;
  DateTime? _lastPocketNotifyAt;

  String _appVersion = '';
  String get appVersion => _appVersion;

  String get _pocketTargetLabel {
    if (_runMode == 'drag') return _activeDragTarget.label;
    if (_activeIntervalTarget == RaceIntervalTarget.custom) {
      return '${_customIntervalStartSpeed.round()}-${_customIntervalEndSpeed.round()}';
    }
    return _activeIntervalTarget.label;
  }

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

    FlutterForegroundTask.addTaskDataCallback(_onPocketTaskData);

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
        if (!_isRideRecording) {
          _isArmed = false;
          _metrics = _physicsEngine.reset();
          _lastGpsUpdateTime = null;
          _recentSpeeds.clear();
          WakelockPlus.disable();
          unawaited(PocketForegroundService.stop());
        } else {
          _startReconnectLoop();
          unawaited(_updateLoggerNotification());
        }
      } else {
        _stopReconnectLoop();
        _applyScreenPolicy();
        if (_isLoggerMode && !_isRideRecording) {
          unawaited(startRideRecording());
        } else if (_isRideRecording) {
          unawaited(_updateLoggerNotification());
        }
      }
      _needsUiUpdate = true;
    });

    _nmeaSubscription = _bleService.nmeaStream.listen((sentence) {
      final data = NmeaParser.parse(sentence);
      if (data != null) {
        bool updated = false;

        if (data.satellites != null) {
          _satellites = data.satellites!;
          updated = true;
        }

        if (data.hdop != null) {
          _hdop = data.hdop!;
          updated = true;
        }

        if (data.altitude != null) {
          _altitude = data.altitude!;
          updated = true;
        }

        if (data.latitude != null) {
          _latitude = data.latitude;
          updated = true;
        }

        if (data.longitude != null) {
          _longitude = data.longitude;
          updated = true;
        }

        if (data.speedKmh != null) {
          _recentSpeeds.add(data.speedKmh!);
          if (_recentSpeeds.length > 5) {
            _recentSpeeds.removeAt(0);
          }

          final wasRunning = _metrics.isRunning;

          _metrics = _physicsEngine.updateMetrics(
            _metrics,
            data.speedKmh!,
            _altitude,
            isArmed: _isArmed && !_isLoggerMode,
            runMode: _runMode,
            targetDistance: targetDistance,
            targetDistanceUnit: targetDistanceUnit,
            targetStartSpeed: targetStartSpeed,
            targetEndSpeed: targetEndSpeed,
            targetSpeedUnit: targetSpeedUnit,
            intervalStartSpeed: intervalStartSpeed,
            intervalEndSpeed: intervalEndSpeed,
            gpsTimeSeconds: data.timeSeconds,
          );
          final isRunning = _metrics.isRunning;

          if (isRunning) {
            _lastGpsUpdateTime = DateTime.now();
            final now = DateTime.now();
            if (_lastPocketNotifyAt == null ||
                now.difference(_lastPocketNotifyAt!) >
                    const Duration(seconds: 1)) {
              _lastPocketNotifyAt = now;
              unawaited(_updatePocketRunningNotification());
            }
          } else {
            _lastGpsUpdateTime = null;
            if (wasRunning) {
              _isArmed = false; // Auto-disarm on completion
            }
          }

          // Check if run just finished
          if (wasRunning && !isRunning && _metrics.history.isNotEmpty) {
            unawaited(_finalizeCompletedRun(_metrics));
          } else if (!wasRunning && isRunning) {
            unawaited(_updatePocketRunningNotification());
          }

          updated = true;
        }

        if (_isRideRecording &&
            _latitude != null &&
            _longitude != null &&
            (data.latitude != null ||
                data.longitude != null ||
                data.speedKmh != null)) {
          final speed = data.speedKmh ?? _metrics.speedKmh;
          unawaited(
            _rideRecorder.appendTrackPoint(
              latitude: _latitude!,
              longitude: _longitude!,
              altitudeMeters: _altitude,
              speedKmh: speed,
            ),
          );
          unawaited(
            _rideRecorder.appendGpsRow(
              latitude: _latitude!,
              longitude: _longitude!,
              altitudeMeters: _altitude,
              speedKmh: speed,
              hdop: _hdop > 0 ? _hdop : null,
              satellites: _satellites > 0 ? _satellites : null,
            ),
          );
          if (_rideRecorder.trackPointCount % 25 == 0) {
            unawaited(_updateLoggerNotification());
          }
        }

        if (updated) {
          _needsUiUpdate = true;
        }
      }
    });

    _imuSubscription = _bleService.imuStream.listen((csv) {
      try {
        final parts = csv.split(',');
        if (parts.length >= 3) {
          // Assuming BMI160 format: "X,Y,Z" raw integers
          final ax = int.parse(parts[0].trim()) / 16384.0;
          final ay = int.parse(parts[1].trim()) / 16384.0;
          final az = int.parse(parts[2].trim()) / 16384.0;

          // We'll use the Y axis for longitudinal G-force (front to back) after a 90-degree pivot
          double gForce = ay;

          if (_isRideRecording && _rideRecorder.isRecording) {
            final started = _rideRecorder.startedAt;
            if (started != null) {
              unawaited(
                _rideRecorder.appendImuSample(
                  elapsedMs:
                      DateTime.now().difference(started).inMilliseconds,
                  axG: ax,
                  ayG: ay,
                  azG: az,
                ),
              );
            }
          }

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
      _bleReconnectId = device.remoteId.str;
      notifyListeners();
      if (_isLoggerMode && !_isRideRecording) {
        unawaited(startRideRecording());
      }
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

  Future<void> _saveRunToHistory(RaceMetrics runMetrics) async {
    final duration = runMetrics.elapsedTime;
    final maxSpeed = runMetrics.history.isNotEmpty
        ? runMetrics.history.map((e) => e.speedKmh).reduce(max)
        : 0.0;

    // Filter out creeping / GPS wander blips
    if (duration >= 1.0 && maxSpeed >= 10.0) {
      final vehicle = activeVehicle;
      final runId = DateTime.now().millisecondsSinceEpoch.toString();

      final savedRun = SavedRun(
        id: runId,
        dateTime: DateTime.now(),
        metrics: runMetrics,
        temperature: null,
        humidity: null,
        vehicleId: vehicle?.id,
        vehicleName: vehicle?.displayName,
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

  void toggleSpeedUnit() {
    _isMetric = !_isMetric;
    _syncActiveTargetToUnit();
    if (_isMetric) {
      _customIntervalStartSpeed = (_customIntervalStartSpeed / 0.621371)
          .roundToDouble();
      _customIntervalEndSpeed = (_customIntervalEndSpeed / 0.621371)
          .roundToDouble();
    } else {
      _customIntervalStartSpeed = (_customIntervalStartSpeed * 0.621371)
          .roundToDouble();
      _customIntervalEndSpeed = (_customIntervalEndSpeed * 0.621371)
          .roundToDouble();
    }
    _saveSettings();
    notifyListeners();
  }

  void setActiveDragTarget(RaceDragTarget target) {
    if (_activeDragTarget != target) {
      _activeDragTarget = target;
      _isArmed = false; // Disarm on target change
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      unawaited(PocketForegroundService.stop());
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
        _customIntervalStartSpeed = (_customIntervalStartSpeed / 0.621371)
            .roundToDouble();
        _customIntervalEndSpeed = (_customIntervalEndSpeed / 0.621371)
            .roundToDouble();
      } else {
        _customIntervalStartSpeed = (_customIntervalStartSpeed * 0.621371)
            .roundToDouble();
        _customIntervalEndSpeed = (_customIntervalEndSpeed * 0.621371)
            .roundToDouble();
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
      } else if (_activeIntervalTarget == RaceIntervalTarget.zeroToOneThirtyMph) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToTwoHundredKmh;
      } else if (_activeIntervalTarget == RaceIntervalTarget.sixtyToOneHundredMph) {
        _activeIntervalTarget = RaceIntervalTarget.oneHundredToOneSixtyKmh;
      } else if (_activeIntervalTarget == RaceIntervalTarget.zeroToOneHundredMph) {
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
      } else if (_activeIntervalTarget == RaceIntervalTarget.zeroToTwoHundredKmh) {
        _activeIntervalTarget = RaceIntervalTarget.zeroToOneThirtyMph;
      } else if (_activeIntervalTarget == RaceIntervalTarget.oneHundredToOneSixtyKmh) {
        _activeIntervalTarget = RaceIntervalTarget.sixtyToOneHundredMph;
      } else if (_activeIntervalTarget == RaceIntervalTarget.zeroToOneSixtyKmh) {
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

  Future<void> setPocketMode(bool value) async {
    if (_pocketMode == value) return;
    _pocketMode = value;
    _saveSettings();
    _applyScreenPolicy();
    if (_isRideRecording) {
      // Logger owns the FGS while recording.
      notifyListeners();
      return;
    }
    if (_pocketMode) {
      if (_isArmed || _metrics.isRunning) {
        await _startPocketService();
        if (_metrics.isRunning) {
          await _updatePocketRunningNotification();
        }
      }
    } else {
      await PocketForegroundService.stop();
    }
    notifyListeners();
  }

  void _applyScreenPolicy() {
    if (_isRideRecording) {
      WakelockPlus.disable();
      return;
    }
    if (_isConnected && !_pocketMode) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  Future<void> toggleArm() async {
    if (_isLoggerMode) return;
    if (_metrics.isRunning) {
      _isArmed = false;
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      await PocketForegroundService.stop();
    } else {
      _isArmed = !_isArmed;
      if (_isArmed) {
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
        if (_pocketMode) {
          await _startPocketService();
        } else {
          _applyScreenPolicy();
          await PocketForegroundService.stop();
        }
      } else {
        await PocketForegroundService.stop();
      }
    }
    notifyListeners();
  }

  Future<String?> setLoggerMode(bool enabled) async {
    if (_isLoggerMode == enabled) return null;

    if (enabled) {
      _isLoggerMode = true;
      _isArmed = false;
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      await PocketForegroundService.stop();
      notifyListeners();
      if (_isConnected) {
        return await startRideRecording();
      }
      return null;
    }

    await stopRideRecording();
    _isLoggerMode = false;
    _applyScreenPolicy();
    notifyListeners();
    return null;
  }

  void setLoggerProject(String? tag) {
    final normalized =
        tag == null || tag.isEmpty || tag == 'none' ? null : tag;
    if (_loggerProject == normalized) return;
    _loggerProject = normalized;
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setLoggerConfiguration(String value) {
    if (_loggerConfiguration == value) return;
    _loggerConfiguration = value;
    unawaited(_saveSettings());
    notifyListeners();
  }

  Future<String?> startRideRecording() async {
    if (_isRideRecording) return null;
    if (!_isConnected) {
      return 'Connect OpenDragy to start logging.';
    }

    await PocketForegroundService.requestPermissions();
    await _rideRecorder.start(
      vehicleName: activeVehicle?.displayName,
      projectTag: _loggerProject,
      configuration: _loggerConfiguration,
    );
    await PocketForegroundService.startLogging(
      subtitle: 'Logger · 0 pts',
    );
    _isRideRecording = true;
    _applyScreenPolicy();
    _needsUiUpdate = true;
    notifyListeners();
    return null;
  }

  Future<File?> stopRideRecording() async {
    if (!_isRideRecording) return null;
    _stopReconnectLoop();
    final file = await _rideRecorder.stop(
      vehicleName: activeVehicle?.displayName,
    );
    await PocketForegroundService.stop();
    _isRideRecording = false;
    _applyScreenPolicy();
    _needsUiUpdate = true;
    notifyListeners();
    return file;
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    if (!_isRideRecording || _bleReconnectId == null) return;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_tryReconnectBle());
    });
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _tryReconnectBle() async {
    if (!_isRideRecording || _isConnected || _bleReconnectId == null) {
      return;
    }
    try {
      final device = BluetoothDevice.fromId(_bleReconnectId!);
      await connect(device);
    } catch (_) {}
  }

  Future<void> _updateLoggerNotification() async {
    if (!_isRideRecording) return;
    final status = _isConnected ? 'GPS live' : 'GPS paused';
    final pts = _rideRecorder.trackPointCount;
    final project = _loggerProject != null ? ' · proj $_loggerProject' : '';
    await PocketForegroundService.update(
      title: 'OpenDragy — Logger',
      subtitle: '$status · $pts pts$project',
      showStop: true,
      showDisarm: false,
    );
  }

  Future<void> _startPocketService() async {
    if (!_pocketMode || _isLoggerMode || _isRideRecording) return;
    await PocketForegroundService.requestPermissions();
    await PocketForegroundService.startArmed(
      subtitle: 'Target: $_pocketTargetLabel — screen may turn off',
    );
  }

  Future<void> _updatePocketRunningNotification() async {
    if (!await PocketForegroundService.isRunning) return;
    await PocketForegroundService.update(
      title: 'OpenDragy — Running',
      subtitle:
          '$_pocketTargetLabel · ${_metrics.elapsedTime.toStringAsFixed(2)} s',
      showStop: true,
      showDisarm: false,
    );
  }

  Future<void> _finalizeCompletedRun(RaceMetrics metrics) async {
    await _saveRunToHistory(metrics);
    if (!await PocketForegroundService.isRunning) return;
    await PocketForegroundService.update(
      title: 'OpenDragy — Saved',
      subtitle:
          '${metrics.elapsedTime.toStringAsFixed(2)} s · $_pocketTargetLabel',
      showDisarm: false,
      showStop: false,
    );
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!_isArmed && !_metrics.isRunning) {
      await PocketForegroundService.stop();
    }
  }

  void _onPocketTaskData(Object data) {
    if (data is! Map) return;
    if (data['ping'] == true) {
      if (_isRideRecording) {
        unawaited(_rideRecorder.flush());
        unawaited(_updateLoggerNotification());
      }
      return;
    }
    final action = data['action']?.toString();
    if (action == 'stop') {
      if (_isLoggerMode || _isRideRecording) {
        unawaited(_handleLoggerStopFromNotification());
      } else {
        unawaited(_handlePocketStop());
      }
    } else if (action == 'disarm') {
      unawaited(_handlePocketDisarm());
    }
  }

  Future<void> _handleLoggerStopFromNotification() async {
    await setLoggerMode(false);
    await PocketForegroundService.bringAppToForeground();
  }

  Future<void> _handlePocketStop() async {
    if (_metrics.isRunning) {
      _isArmed = false;
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      notifyListeners();
    }
    await PocketForegroundService.stop();
    await PocketForegroundService.bringAppToForeground();
  }

  Future<void> _handlePocketDisarm() async {
    _isArmed = false;
    if (!_metrics.isRunning) {
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
    }
    notifyListeners();
    await PocketForegroundService.stop();
    await PocketForegroundService.bringAppToForeground();
  }

  void setRunMode(String mode) {
    if (_runMode != mode) {
      _runMode = mode;
      _isArmed = false; // Disarm on mode change
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      unawaited(PocketForegroundService.stop());
      _saveSettings();
      notifyListeners();
    }
  }

  void setActiveIntervalTarget(RaceIntervalTarget target) {
    if (_activeIntervalTarget != target) {
      _activeIntervalTarget = target;
      _isArmed = false; // Disarm on target change
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      unawaited(PocketForegroundService.stop());
      _saveSettings();
      notifyListeners();
    }
  }

  void setCustomIntervalRange(double start, double end) {
    _customIntervalStartSpeed = start.roundToDouble();
    _customIntervalEndSpeed = end.roundToDouble();
    _isArmed = false; // Disarm on range change
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    unawaited(PocketForegroundService.stop());
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final data = await _settingsService.load();
    _isMetric = data['isMetric'] as bool? ?? false;
    _tempInCelsius = data['tempInCelsius'] as bool? ?? true;
    _useNhraRules = data['useNhraRules'] as bool? ?? true;
    _pocketMode = data['pocketMode'] as bool? ?? false;
    _loggerProject = data['loggerProject'] as String?;
    _loggerConfiguration = data['loggerConfiguration'] as String? ?? '';
    _runMode = data['runMode'] as String? ?? 'drag';
    _applyScreenPolicy();

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
      'pocketMode': _pocketMode,
      'loggerProject': _loggerProject,
      'loggerConfiguration': _loggerConfiguration,
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
    FlutterForegroundTask.removeTaskDataCallback(_onPocketTaskData);
    _stopReconnectLoop();
    _uiTimer?.cancel();
    _nmeaSubscription?.cancel();
    _imuSubscription?.cancel();
    _connectionSubscription?.cancel();
    WakelockPlus.disable();
    if (_isRideRecording) {
      unawaited(_rideRecorder.stop(vehicleName: activeVehicle?.displayName));
    }
    unawaited(PocketForegroundService.stop());
    super.dispose();
  }
}


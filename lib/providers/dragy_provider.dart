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
  zeroToSixtyMph('0-60 mph'),
  zeroToOneHundredMph('0-100 mph'),
  fiftyToSeventyFiveMph('50-75 mph'),
  sixtyToOneHundredMph('60-100 mph'),
  sixtyToOneThirtyMph('60-130 mph'),
  zeroToOneThirtyMph('0-130 mph'),
  zeroToOneHundredKmh('0-100 km/h'),
  zeroToOneSixtyKmh('0-160 km/h'),
  eightyToOneTwentyKmh('80-120 km/h'),
  oneHundredToOneSixtyKmh('100-160 km/h'),
  oneHundredToTwoHundredKmh('100-200 km/h'),
  zeroToTwoHundredKmh('0-200 km/h'),
  custom('Custom Range...');

  final String label;
  const RaceIntervalTarget(this.label);
}

class DragyProvider extends ChangeNotifier {
  final BleService _bleService = BleService();
  final PhysicsEngine _physicsEngine = PhysicsEngine();
  final HistoryService _historyService = HistoryService();
  final GarageService _garageService = GarageService();
  final SettingsService _settingsService = SettingsService();
  final WeatherService _weatherService = WeatherService();

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

  bool _showRollout = false;
  bool get showRollout => _showRollout;

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
    if (_metrics.isRunning && _lastGpsUpdateTime != null) {
      final delta =
          DateTime.now().difference(_lastGpsUpdateTime!).inMicroseconds /
          1000000.0;
      final clampedDelta = delta.clamp(0.0, _physicsEngine.lastValidDt);
      return _metrics.elapsedTime + clampedDelta;
    }
    return _metrics.elapsedTime;
  }

  StreamSubscription? _nmeaSubscription;
  StreamSubscription? _imuSubscription;
  StreamSubscription? _connectionSubscription;

  final List<double> _recentSpeeds = [];

  List<SavedRun> _savedRuns = [];
  List<SavedRun> get savedRuns => _savedRuns;

  Timer? _uiTimer;
  bool _needsUiUpdate = false;

  String _appVersion = '';
  String get appVersion => _appVersion;

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
        _isArmed = false;
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
        _recentSpeeds.clear();
        WakelockPlus.disable();
      } else {
        WakelockPlus.enable();
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
            isArmed: _isArmed,
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
          } else {
            _lastGpsUpdateTime = null;
            if (wasRunning) {
              _isArmed = false; // Auto-disarm on completion
            }
          }

          // Check if run just finished
          if (wasRunning && !isRunning && _metrics.history.isNotEmpty) {
            _saveRunToHistory(_metrics);
          }

          updated = true;
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

  void setShowRollout(bool value) {
    if (_showRollout != value) {
      _showRollout = value;
      _saveSettings();
      notifyListeners();
    }
  }

  void toggleArm() {
    if (_metrics.isRunning) {
      _isArmed = false;
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
    } else {
      _isArmed = !_isArmed;
      if (_isArmed) {
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
      }
    }
    notifyListeners();
  }

  void setRunMode(String mode) {
    if (_runMode != mode) {
      _runMode = mode;
      _isArmed = false; // Disarm on mode change
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
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final data = await _settingsService.load();
    _isMetric = data['isMetric'] as bool? ?? false;
    _tempInCelsius = data['tempInCelsius'] as bool? ?? true;
    _showRollout = data['showRollout'] as bool? ?? false;
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
      'showRollout': _showRollout,
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
    _nmeaSubscription?.cancel();
    _imuSubscription?.cancel();
    _connectionSubscription?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

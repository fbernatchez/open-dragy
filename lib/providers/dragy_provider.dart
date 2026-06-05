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
  eighthMile('1/8 Mile'),
  thousandFeet('1000 ft'),
  quarterMile('1/4 Mile'),
  halfMile('1/2 Mile');

  final String label;
  const RaceDragTarget(this.label);
}

enum RaceRollingTarget {
  zeroToSixtyMph('0-60 mph'),
  sixtyToOneThirtyMph('60-130 mph'),
  zeroToOneHundredKmh('0-100 km/h'),
  oneHundredToTwoHundredKmh('100-200 km/h'),
  custom('Custom Range...');

  final String label;
  const RaceRollingTarget(this.label);
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

  bool get stopAtQuarterMile => _activeDragTarget == RaceDragTarget.quarterMile;

  // --- Settings ---
  bool _tempInCelsius = true;
  bool get tempInCelsius => _tempInCelsius;

  // --- Arming & Run Modes ---
  bool _isArmed = false;
  bool get isArmed => _isArmed;

  String _runMode = 'drag';
  String get runMode => _runMode;

  RaceRollingTarget _activeRollingTarget = RaceRollingTarget.sixtyToOneThirtyMph;
  RaceRollingTarget get activeRollingTarget => _activeRollingTarget;

  double _customRollingStartSpeed = 100.0;
  double get customRollingStartSpeed => _customRollingStartSpeed;

  double _customRollingEndSpeed = 200.0;
  double get customRollingEndSpeed => _customRollingEndSpeed;

  double get rollingStartSpeed {
    switch (_activeRollingTarget) {
      case RaceRollingTarget.sixtyToOneThirtyMph:
        return 96.5606;
      case RaceRollingTarget.oneHundredToTwoHundredKmh:
        return 100.0;
      case RaceRollingTarget.zeroToSixtyMph:
        return 0.0;
      case RaceRollingTarget.zeroToOneHundredKmh:
        return 0.0;
      case RaceRollingTarget.custom:
        return _isMetric ? _customRollingStartSpeed : _customRollingStartSpeed / 0.621371;
    }
  }

  double get rollingEndSpeed {
    switch (_activeRollingTarget) {
      case RaceRollingTarget.sixtyToOneThirtyMph:
        return 209.2147;
      case RaceRollingTarget.oneHundredToTwoHundredKmh:
        return 200.0;
      case RaceRollingTarget.zeroToSixtyMph:
        return 96.5606;
      case RaceRollingTarget.zeroToOneHundredKmh:
        return 100.0;
      case RaceRollingTarget.custom:
        return _isMetric ? _customRollingEndSpeed : _customRollingEndSpeed / 0.621371;
    }
  }

  double get customRollingStartSpeedUserUnit {
    return _customRollingStartSpeed;
  }

  double get customRollingEndSpeedUserUnit {
    return _customRollingEndSpeed;
  }

  String get activeDragTargetLabel {
    return _activeDragTarget.label;
  }

  String get activeRollingTargetLabel {
    if (_activeRollingTarget == RaceRollingTarget.custom) {
      final start = _customRollingStartSpeed.round();
      final end = _customRollingEndSpeed.round();
      final unit = _isMetric ? 'km/h' : 'mph';
      return '$start-$end $unit';
    } else {
      return _activeRollingTarget.label;
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
      final clampedDelta = delta.clamp(0.0, 0.1);
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
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
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
          final targetLabel = _runMode == 'drag' ? activeDragTargetLabel : activeRollingTargetLabel;

          _metrics = _physicsEngine.updateMetrics(
            _metrics,
            data.speedKmh!,
            _altitude,
            isArmed: _isArmed,
            runMode: _runMode,
            targetLabel: targetLabel,
            rollingStartSpeed: rollingStartSpeed,
            rollingEndSpeed: rollingEndSpeed,
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
            _gForceCalibrationOffset = _gForceCalibrationOffset * (1.0 - alpha) + gForce * alpha;
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
      double temp = 15.0 + Random().nextDouble() * 10.0; // fallback 15-25°C
      double humid = 40.0 + Random().nextDouble() * 30.0; // fallback 40-70%

      final lat = _latitude;
      final lon = _longitude;
      if (lat != null && lon != null) {
        final weather = await _weatherService.fetchWeather(lat, lon);
        if (weather != null) {
          temp = weather['temp']!;
          humid = weather['humid']!;
        }
      }

      final vehicle = activeVehicle;
      final savedRun = SavedRun(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        dateTime: DateTime.now(),
        metrics: runMetrics,
        temperature: temp,
        humidity: humid,
        vehicleId: vehicle?.id,
        vehicleName: vehicle?.displayName,
      );
      await _historyService.saveRun(savedRun);
      _savedRuns.insert(0, savedRun);
      _needsUiUpdate = true;
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
      _customRollingStartSpeed = (_customRollingStartSpeed / 0.621371).roundToDouble();
      _customRollingEndSpeed = (_customRollingEndSpeed / 0.621371).roundToDouble();
    } else {
      _customRollingStartSpeed = (_customRollingStartSpeed * 0.621371).roundToDouble();
      _customRollingEndSpeed = (_customRollingEndSpeed * 0.621371).roundToDouble();
    }
    _saveSettings();
    notifyListeners();
  }

  void setStopAtQuarterMile(bool value) {
    setActiveDragTarget(value ? RaceDragTarget.quarterMile : RaceDragTarget.halfMile);
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
        _customRollingStartSpeed = (_customRollingStartSpeed / 0.621371).roundToDouble();
        _customRollingEndSpeed = (_customRollingEndSpeed / 0.621371).roundToDouble();
      } else {
        _customRollingStartSpeed = (_customRollingStartSpeed * 0.621371).roundToDouble();
        _customRollingEndSpeed = (_customRollingEndSpeed * 0.621371).roundToDouble();
      }
      _saveSettings();
      notifyListeners();
    }
  }

  void _syncActiveTargetToUnit() {
    if (_isMetric) {
      if (_activeRollingTarget == RaceRollingTarget.sixtyToOneThirtyMph) {
        _activeRollingTarget = RaceRollingTarget.oneHundredToTwoHundredKmh;
      } else if (_activeRollingTarget == RaceRollingTarget.zeroToSixtyMph) {
        _activeRollingTarget = RaceRollingTarget.zeroToOneHundredKmh;
      }
    } else {
      if (_activeRollingTarget == RaceRollingTarget.oneHundredToTwoHundredKmh) {
        _activeRollingTarget = RaceRollingTarget.sixtyToOneThirtyMph;
      } else if (_activeRollingTarget == RaceRollingTarget.zeroToOneHundredKmh) {
        _activeRollingTarget = RaceRollingTarget.zeroToSixtyMph;
      }
    }
  }

  void setTempInCelsius(bool value) {
    _tempInCelsius = value;
    _saveSettings();
    notifyListeners();
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



  void setActiveRollingTarget(RaceRollingTarget target) {
    if (_activeRollingTarget != target) {
      _activeRollingTarget = target;
      _isArmed = false; // Disarm on target change
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      _saveSettings();
      notifyListeners();
    }
  }

  void setCustomRollingRange(double start, double end) {
    _customRollingStartSpeed = start.roundToDouble();
    _customRollingEndSpeed = end.roundToDouble();
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
    _runMode = data['runMode'] as String? ?? 'drag';
    
    final dragTargetName = data['activeDragTarget'] as String?;
    _activeDragTarget = RaceDragTarget.values.firstWhere(
      (e) => e.name == dragTargetName,
      orElse: () => RaceDragTarget.quarterMile,
    );

    final rollingTargetName = data['activeRollingTarget'] as String?;
    _activeRollingTarget = RaceRollingTarget.values.firstWhere(
      (e) => e.name == rollingTargetName,
      orElse: () => RaceRollingTarget.sixtyToOneThirtyMph,
    );

    _customRollingStartSpeed = (data['customRollingStartSpeed'] as num?)?.toDouble() ?? 100.0;
    _customRollingEndSpeed = (data['customRollingEndSpeed'] as num?)?.toDouble() ?? 200.0;
    _syncActiveTargetToUnit();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _settingsService.save({
      'isMetric': _isMetric,
      'tempInCelsius': _tempInCelsius,
      'runMode': _runMode,
      'activeDragTarget': _activeDragTarget.name,
      'stopAtQuarterMile': stopAtQuarterMile,
      'activeRollingTarget': _activeRollingTarget.name,
      'customRollingStartSpeed': _customRollingStartSpeed.round(),
      'customRollingEndSpeed': _customRollingEndSpeed.round(),
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

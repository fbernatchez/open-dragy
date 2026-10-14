import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
import '../models/race_test.dart';
import '../services/tts_service.dart';
import '../services/audio_recording_service.dart';
import '../services/firmware_service.dart';
import 'dart:io';
import 'telemetry_provider.dart';

export '../models/race_test.dart';

class DragyProvider extends ChangeNotifier {
  final BleService _bleService = BleService();
  final PhysicsEngine _physicsEngine = PhysicsEngine();
  final HistoryService _historyService = HistoryService();
  final GarageService _garageService = GarageService();
  final SettingsService _settingsService = SettingsService();
  final WeatherService _weatherService = WeatherService();
  final TtsService _ttsService = TtsService();
  final AudioRecordingService _audioService = AudioRecordingService();
  final FirmwareService _firmwareService = FirmwareService();

  late final TelemetryProvider telemetry;

  double? get latitude => telemetry.latitude;
  double? get longitude => telemetry.longitude;

  double? _currentTemperature;
  double? get currentTemperature => _currentTemperature;

  double? _currentHumidity;
  double? get currentHumidity => _currentHumidity;

  int? _currentWeatherCode;
  int? get currentWeatherCode => _currentWeatherCode;

  Timer? _weatherTimer;
  bool _isFetchingWeather = false;

  RaceMetrics get metrics => telemetry.metrics;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  int get satellites => telemetry.satellites;
  double get hdop => telemetry.hdop;
  double get altitude => telemetry.altitude;

  bool _isMetric = false;
  bool get isMetric => _isMetric;

  RaceDragTest _activeDragTest = RaceDragTest.quarterMile;
  RaceDragTest get activeDragTest => _activeDragTest;

  // --- Settings ---
  bool _tempInCelsius = true;
  bool get tempInCelsius => _tempInCelsius;

  bool _useNhraRules = true;
  bool get useNhraRules => _useNhraRules;

  bool _enableTts = true;
  bool get enableTts => _enableTts;

  bool _enableAudioRecording = true;
  bool get enableAudioRecording => _enableAudioRecording;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  // --- Arming & Run Modes ---
  bool get isArmed => telemetry.isArmed;

  RunMode _runMode = RunMode.drag;
  RunMode get runMode => _runMode;

  RaceIntervalTest _activeIntervalTest = RaceIntervalTest.sixtyToOneThirtyMph;
  RaceIntervalTest get activeIntervalTest => _activeIntervalTest;

  double _customIntervalStartSpeed = 100.0;
  double get customIntervalStartSpeed => _customIntervalStartSpeed;

  double _customIntervalEndSpeed = 200.0;
  double get customIntervalEndSpeed => _customIntervalEndSpeed;

  List<String> _enabledTests = officialTests.map((t) => t.id).toList();
  List<String> get enabledTests => List.unmodifiable(_enabledTests);

  List<RaceTest> _customTests = [];
  List<RaceTest> get customTests => List.unmodifiable(_customTests);

  double get intervalStartSpeed {
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      return _isMetric
          ? _customIntervalStartSpeed
          : UnitConverter.mphToKmh(_customIntervalStartSpeed);
    }
    return _activeIntervalTest.startSpeedKmh ?? 0.0;
  }

  double get intervalEndSpeed {
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      return _isMetric
          ? _customIntervalEndSpeed
          : UnitConverter.mphToKmh(_customIntervalEndSpeed);
    }
    return _activeIntervalTest.endSpeedKmh ?? 0.0;
  }

  double get customIntervalStartSpeedUserUnit {
    return _customIntervalStartSpeed;
  }

  double get customIntervalEndSpeedUserUnit {
    return _customIntervalEndSpeed;
  }

  String get activeDragTestLabel {
    return _activeDragTest.label;
  }

  String get activeIntervalTestLabel {
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      final start = _customIntervalStartSpeed.round();
      final end = _customIntervalEndSpeed.round();
      final unit = _isMetric ? 'km/h' : 'mph';
      return '$start-$end $unit';
    } else {
      return _activeIntervalTest.label;
    }
  }

  double? get testDistance =>
      _runMode == RunMode.drag ? _activeDragTest.distance : null;

  DistanceUnit? get testDistanceUnit =>
      _runMode == RunMode.drag ? _activeDragTest.distanceUnit : null;

  double? get testStartSpeed {
    if (_runMode != RunMode.interval) return null;
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      return _customIntervalStartSpeed;
    }
    return _activeIntervalTest.startSpeedUserUnit;
  }

  double? get testEndSpeed {
    if (_runMode != RunMode.interval) return null;
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      return _customIntervalEndSpeed;
    }
    return _activeIntervalTest.endSpeedUserUnit;
  }

  SpeedUnit? get testSpeedUnit {
    if (_runMode != RunMode.interval) return null;
    if (_activeIntervalTest == RaceIntervalTest.custom) {
      return _isMetric ? SpeedUnit.kmh : SpeedUnit.mph;
    }
    return _activeIntervalTest.speedUnit ??
        (_isMetric ? SpeedUnit.kmh : SpeedUnit.mph);
  }

  bool get isSpeedConstant => telemetry.isSpeedConstant;

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

  int _boxPivotAngle = 0;
  int get boxPivotAngle => _boxPivotAngle;

  double get liveElapsedTime => telemetry.liveElapsedTime;

  StreamSubscription? _connectionSubscription;

  List<SavedRun> _savedRuns = [];
  List<SavedRun> get savedRuns => _savedRuns;

  String _appVersion = '';
  String get appVersion => _appVersion;

  String _firmwareVersion = '';
  String get firmwareVersion => _firmwareVersion;

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      notifyListeners();
    } catch (_) {}
  }

  DragyProvider() {
    telemetry = TelemetryProvider(
      bleService: _bleService,
      physicsEngine: _physicsEngine,
      ttsService: _ttsService,
      audioService: _audioService,
      dragyProvider: this,
    );
    loadSavedRuns();
    _loadGarage();
    _loadSettings();
    _loadAppVersion();
    _startWeatherTimer();

    _connectionSubscription = _bleService.connectionStateStream.listen((
      connected,
    ) {
      _isConnected = connected;
      if (!connected) {
        _connectedDevice = null;
        _firmwareVersion = '';
      }
      notifyListeners();
    });

    _bleService.firmwareVersionStream.listen((version) {
      _firmwareVersion = version;
      notifyListeners();
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

  Future<void> performFirmwareUpdate(
    String requestedVersion,
    void Function(double) onProgress,
  ) async {
    // 1. Fetch bytes from the remote service
    final firmwareBytes = await _firmwareService.fetchBestFirmwareBytes(
      requestedVersion,
    );

    // 2. Pass bytes to BLE service
    await _bleService.performOtaUpdate(firmwareBytes, onProgress);
  }

  void resetRace() => telemetry.resetRace();

  // --- Local History Methods ---

  Future<void> loadSavedRuns() async {
    _savedRuns = await _historyService.loadRuns();
    notifyListeners();
  }

  Future<void> saveRun(
    RaceMetrics runMetrics, {
    String? audioFilePath,
    double? audioStartOffset,
  }) async {
    await _saveRunToHistory(
      runMetrics,
      audioFilePath: audioFilePath,
      audioStartOffset: audioStartOffset,
    );
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
      notifyListeners();

      // Fetch weather asynchronously in the background if coordinates are available
      final lat = latitude;
      final lon = longitude;
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
    setMetric(!_isMetric);
  }

  void setactiveDragTest(RaceDragTest target) {
    if (_activeDragTest != target) {
      _activeDragTest = target;
      telemetry.resetRace();
      _saveSettings();
      notifyListeners();
    }
  }

  void setActiveDragTest(RaceDragTest target) => setactiveDragTest(target);

  // --- Settings Methods ---

  void setMetric(bool isMetric) {
    if (_isMetric != isMetric) {
      _isMetric = isMetric;

      final convert =
          _isMetric ? UnitConverter.mphToKmh : UnitConverter.kmhToMph;
      _customIntervalStartSpeed =
          convert(_customIntervalStartSpeed).roundToDouble();
      _customIntervalEndSpeed = convert(_customIntervalEndSpeed).roundToDouble();

      _syncActiveTestToUnit();
      _saveSettings();
      notifyListeners();
    }
  }

  void _syncActiveTestToUnit() {
    if (_activeIntervalTest != RaceIntervalTest.custom &&
        (_activeIntervalTest.speedUnit == SpeedUnit.kmh) != _isMetric) {
      _activeIntervalTest = _isMetric
          ? RaceIntervalTest.zeroToOneHundredKmh
          : RaceIntervalTest.zeroToSixtyMph;
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
      _saveSettings();
      notifyListeners();
    }
  }

  void setBoxPivotAngle(int angle) {
    final normalized = (angle % 360 + 360) % 360;
    if (_boxPivotAngle != normalized) {
      _boxPivotAngle = normalized;
      _saveSettings();
      notifyListeners();
    }
  }

  static double computeLeveledGForce({
    required int boxPivotAngle,
    required double gx,
    required double gy,
    required double gz,
    double gravX = 0.0,
    double gravY = 0.0,
    double gravZ = 1.0,
  }) =>
      TelemetryProvider.computeLeveledGForce(
        boxPivotAngle: boxPivotAngle,
        gx: gx,
        gy: gy,
        gz: gz,
        gravX: gravX,
        gravY: gravY,
        gravZ: gravZ,
      );

  void toggleArm() => telemetry.toggleArm();
  void arm() => telemetry.arm();
  void disarm() => telemetry.disarm();

  void setRunMode(RunMode mode) {
    if (_runMode != mode) {
      _runMode = mode;
      telemetry.resetRace();
      _saveSettings();
      notifyListeners();
    }
  }

  void setactiveIntervalTest(RaceIntervalTest target) {
    if (_activeIntervalTest != target) {
      _activeIntervalTest = target;
      telemetry.resetRace();
      _saveSettings();
      notifyListeners();
    }
  }

  void setCustomIntervalRange(double start, double end) {
    _customIntervalStartSpeed = start.roundToDouble();
    _customIntervalEndSpeed = end.roundToDouble();
    telemetry.resetRace();
    _saveSettings();
    notifyListeners();
  }

  void addCustomTest(RaceTest target) {
    if (_customTests.any((t) => t.id == target.id)) return;
    _customTests.add(target);
    _customTests.sort(_comparecustomTests);
    _saveSettings();
    notifyListeners();
  }

  static int _comparecustomTests(RaceTest a, RaceTest b) {
    final aIsDistance = a.distance != null;
    final bIsDistance = b.distance != null;
    if (aIsDistance != bIsDistance) return aIsDistance ? 1 : -1;

    if (aIsDistance) {
      return a.distance!.compareTo(b.distance!);
    }

    final startA = a.startSpeed ?? 0.0;
    final startB = b.startSpeed ?? 0.0;
    if (startA != startB) {
      return startA.compareTo(startB);
    }

    final endA = a.endSpeed ?? 0.0;
    final endB = b.endSpeed ?? 0.0;
    return endA.compareTo(endB);
  }

  bool isTestEnabled(String testId) {
    if (testId.startsWith('custom_')) return true;
    if (_customTests.any((t) => t.id == testId)) return true;
    return _enabledTests.contains(testId);
  }

  void toggleTestEnabled(String targetId, bool enabled) {
    if (enabled) {
      if (!_enabledTests.contains(targetId)) {
        _enabledTests.add(targetId);
      }
    } else {
      _enabledTests.remove(targetId);
    }
    _saveSettings();
    notifyListeners();
  }

  void removeCustomTest(String targetId) {
    _customTests.removeWhere((t) => t.id == targetId);
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
    final themeModeStr = data['themeMode'] as String?;
    _themeMode = themeModeStr != null
        ? (ThemeMode.values.asNameMap()[themeModeStr] ?? ThemeMode.system)
        : ThemeMode.system;
    _boxPivotAngle = (data['boxPivotAngle'] as num?)?.toInt() ?? 0;
    final modeStr = data['runMode'] as String?;
    _runMode = modeStr != null
        ? (RunMode.values.asNameMap()[modeStr] ?? RunMode.drag)
        : RunMode.drag;

    final dragTestName = data['activeDragTest'] as String?;
    _activeDragTest = RaceDragTest.values.firstWhere(
      (e) => e.name == dragTestName,
      orElse: () => RaceDragTest.quarterMile,
    );

    final intervalTestName = data['activeIntervalTest'] as String?;
    _activeIntervalTest = RaceIntervalTest.values.firstWhere(
      (e) => e.name == intervalTestName,
      orElse: () => RaceIntervalTest.sixtyToOneThirtyMph,
    );

    _customIntervalStartSpeed =
        (data['customIntervalStartSpeed'] as num?)?.toDouble() ?? 100.0;
    _customIntervalEndSpeed =
        (data['customIntervalEndSpeed'] as num?)?.toDouble() ?? 200.0;

    if (data['enabledTests'] != null) {
      _enabledTests = List<String>.from(data['enabledTests']);
    } else {
      _enabledTests = officialTests.map((t) => t.id).toList();
    }

    if (data['customTests'] != null) {
      _customTests = (data['customTests'] as List)
          .map((e) => RaceTest.fromJson(e as Map<String, dynamic>))
          .toList();
      _customTests.sort(_comparecustomTests);
    } else {
      _customTests = [];
    }

    _syncActiveTestToUnit();

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    await _settingsService.save({
      'isMetric': _isMetric,
      'tempInCelsius': _tempInCelsius,
      'useNhraRules': _useNhraRules,
      'enableTts': _enableTts,
      'enableAudioRecording': _enableAudioRecording,
      'themeMode': _themeMode.name,
      'boxPivotAngle': _boxPivotAngle,
      'runMode': _runMode.name,
      'activeDragTest': _activeDragTest.name,
      'activeIntervalTest': _activeIntervalTest.name,
      'customIntervalStartSpeed': _customIntervalStartSpeed.round(),
      'customIntervalEndSpeed': _customIntervalEndSpeed.round(),
      'enabledTests': _enabledTests,
      'customTests': _customTests.map((t) => t.toJson()).toList(),
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
    try {
      _weatherTimer?.cancel();
      _weatherTimer = null;
      _connectionSubscription?.cancel();
      if (!telemetry.isDisposed) {
        telemetry.dispose();
      }
    } finally {
      super.dispose();
    }
  }

  void _startWeatherTimer() {
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchCurrentWeather();
    });
    // Trigger immediately
    triggerWeatherFetchIfNull();
  }

  void triggerWeatherFetchIfNull() {
    if (_currentTemperature == null && !_isFetchingWeather) {
      _fetchCurrentWeather();
    }
  }

  Future<void> _fetchCurrentWeather() async {
    final lat = latitude;
    final lon = longitude;
    if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
      if (_isFetchingWeather) return;
      _isFetchingWeather = true;
      try {
        final weather = await _weatherService.fetchWeather(lat, lon);
        if (weather != null) {
          _currentTemperature = weather['temp'];
          _currentHumidity = weather['humid'];
          _currentWeatherCode = weather['weatherCode']?.toInt();
          notifyListeners();
        }
      } finally {
        _isFetchingWeather = false;
      }
    }
  }
}

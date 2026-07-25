import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../services/open_dragy_storage.dart';
import '../models/satellite_sv.dart';
import '../utils/nmea_parser.dart';
import '../utils/logger_tags.dart';
import '../utils/ubx_cfg.dart';
import '../utils/ubx_mga.dart';
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
  final OpenDragyStorage _durableStorage = OpenDragyStorage();

  double? _latitude;
  double? get latitude => _latitude;

  double? _longitude;
  double? get longitude => _longitude;

  /// Last known good fix — used as coarse M10 position aiding on connect.
  double? _aidingLatitude;
  double? _aidingLongitude;
  double _aidingAltitude = 0;
  DateTime? _aidingSavedAt;
  DateTime? _lastAidingPersistAt;

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

  double _pdop = 0.0;
  double get pdop => _pdop;

  double _vdop = 0.0;
  double get vdop => _vdop;

  int? _fixQuality;
  int? get fixQuality => _fixQuality;

  int? _fixMode;
  int? get fixMode => _fixMode;

  double _altitude = 0.0;
  double get altitude => _altitude;

  List<SatelliteSv> _skySatellites = const [];
  List<SatelliteSv> get skySatellites => _skySatellites;

  Set<int> _usedPrns = {};
  Set<int> get usedPrns => _usedPrns;

  bool _satelliteDetailActive = false;
  bool get satelliteDetailActive => _satelliteDetailActive;

  final Map<String, List<SatelliteSv>> _gsvByTalker = {};

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

  String _loggerTagsText = '';
  String get loggerTagsText => _loggerTagsText;

  String _loggerNotes = '';
  String get loggerNotes => _loggerNotes;

  List<String> _rankedLoggerTags = [];
  List<String> get loggerSuggestedTags {
    final current = parseLoggerTags(_loggerTagsText)
        .map((t) => t.toLowerCase())
        .toSet();
    return _rankedLoggerTags
        .where((t) => !current.contains(t.toLowerCase()))
        .take(12)
        .toList();
  }

  OpenDragyStorage get durableStorage => _durableStorage;
  bool get hasDurableDataFolder => _durableStorage.hasDataFolder;
  bool get usesPublicDataFolder => _durableStorage.isPublicMode;
  String? get durableDataFolderPath => _durableStorage.publicRootPath;

  static const _openDragyBleName = 'OpenDragy';

  String? _bleReconnectId;
  Timer? _reconnectTimer;
  Timer? _autoConnectTimer;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  bool _autoConnectSuppressed = false;
  bool _autoConnectBusy = false;
  bool _blePermissionsGranted = false;
  bool _isDisposed = false;

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
    unawaited(_bootstrapAppState());
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
        _satelliteDetailActive = false;
        _skySatellites = const [];
        _gsvByTalker.clear();
        if (!_isRideRecording) {
          _isArmed = false;
          _metrics = _physicsEngine.reset();
          _lastGpsUpdateTime = null;
          _recentSpeeds.clear();
          WakelockPlus.disable();
          unawaited(_releasePocketOrKeepAlive());
        } else {
          unawaited(_updateLoggerNotification());
        }
        // Drop / out of range → keep looking for OpenDragy.
        if (!_autoConnectSuppressed) {
          _startAutoConnectLoop();
        }
      } else {
        _stopAutoConnectLoop();
        _stopReconnectLoop();
        _applyScreenPolicy();
        if (_satelliteDetailActive) {
          unawaited(_sendSatelliteDetailConfig(enable: true));
        }
        if (_isLoggerMode && !_isRideRecording) {
          unawaited(startRideRecording());
        } else if (_isRideRecording) {
          unawaited(_updateLoggerNotification());
        } else {
          unawaited(_syncPocketStatusNotification());
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

        if (data.pdop != null) {
          _pdop = data.pdop!;
          updated = true;
        }

        if (data.vdop != null) {
          _vdop = data.vdop!;
          updated = true;
        }

        if (data.fixQuality != null) {
          _fixQuality = data.fixQuality;
          // New GGA epoch — start fresh used-SV set (GSA may follow in pieces).
          _usedPrns = {};
          updated = true;
        }

        if (data.fixMode != null) {
          _fixMode = data.fixMode;
          updated = true;
        }

        if (data.usedPrns != null) {
          _usedPrns = {..._usedPrns, ...data.usedPrns!};
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

        if (data.gsv != null) {
          // ignore: avoid_print
          print(
            '[GPS] GSV ${data.gsv!.talker} '
            '${data.gsv!.messageNumber}/${data.gsv!.totalMessages} '
            'sats+=${data.gsv!.satellites.length}',
          );
          if (_ingestGsv(data.gsv!)) {
            updated = true;
          }
        }

        if (data.latitude != null && data.longitude != null) {
          _rememberAidingFix(
            data.latitude!,
            data.longitude!,
            data.altitude ?? _altitude,
          );
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
    _autoConnectSuppressed = false;
    final success = await _bleService.connectToDevice(device);
    if (success) {
      _connectedDevice = device;
      _bleReconnectId = device.remoteId.str;
      unawaited(_saveSettings());
      notifyListeners();
      unawaited(_injectGpsAiding());
      if (_isLoggerMode && !_isRideRecording) {
        unawaited(startRideRecording());
      }
    }
    return success;
  }

  bool _ingestGsv(NmeaGsvFragment frag) {
    final talker = frag.talker.toUpperCase();
    if (frag.messageNumber == 1) {
      _gsvByTalker[talker] = [];
    }
    final bucket = _gsvByTalker.putIfAbsent(talker, () => []);
    bucket.addAll(frag.satellites);

    if (frag.messageNumber < frag.totalMessages) {
      return false;
    }

    // Rebuild sky list from all talkers once a talker cycle completes.
    final merged = <SatelliteSv>[];
    for (final list in _gsvByTalker.values) {
      merged.addAll(list);
    }
    merged.sort((a, b) {
      final c = a.talker.compareTo(b.talker);
      if (c != 0) return c;
      return a.prn.compareTo(b.prn);
    });
    _skySatellites = merged;
    return true;
  }

  /// While the satellite screen is open, ask M10 for GSV/GSA (~1 Hz).
  Future<void> setSatelliteDetailActive(bool active) async {
    final wasActive = _satelliteDetailActive;
    _satelliteDetailActive = active;
    if (!active) {
      _skySatellites = const [];
      _gsvByTalker.clear();
    }
    notifyListeners();

    if (!_isConnected) {
      // ignore: avoid_print
      print(
        '[GPS] Satellite detail=$active queued '
        '(will send CFG when connected)',
      );
      return;
    }

    // Always (re)send when turning on, or when turning off after being on.
    if (active || wasActive) {
      await _sendSatelliteDetailConfig(enable: active);
    }
  }

  Future<void> _sendSatelliteDetailConfig({required bool enable}) async {
    // PUBX first (NMEA) — works even when UBX-in is disabled on the module.
    final pubxFrames = UbxCfg.pubxDetailFrames(enable: enable);
    final ubxFrames = UbxCfg.ubxDetailFrames(enable: enable);
    // ignore: avoid_print
    print(
      '[GPS] Satellite detail enable=$enable → '
      '${pubxFrames.length} PUBX + ${ubxFrames.length} UBX frames',
    );
    for (final frame in [...pubxFrames, ...ubxFrames]) {
      final ok = await _bleService.writeToGps(frame);
      // ignore: avoid_print
      print('[GPS] cfg write ok=$ok len=${frame.length}');
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Speeds up M10 cold start: phone UTC + last known coarse position.
  Future<void> _injectGpsAiding() async {
    try {
      final timeMsg = UbxMga.timeUtc(DateTime.now().toUtc());
      await _bleService.writeToGps(timeMsg);

      final lat = _aidingLatitude;
      final lon = _aidingLongitude;
      final savedAt = _aidingSavedAt;
      if (lat == null || lon == null || savedAt == null) return;

      final age = DateTime.now().difference(savedAt);
      if (age.inDays > 30) return;

      final posMsg = UbxMga.posLlh(
        latitudeDeg: lat,
        longitudeDeg: lon,
        altitudeMeters: _aidingAltitude,
        posAccMeters: UbxMga.accuracyMetersForAge(age),
      );
      await Future.delayed(const Duration(milliseconds: 40));
      await _bleService.writeToGps(posMsg);
      // ignore: avoid_print
      print(
        '[GPS] Aiding injected (time + pos age=${age.inHours}h '
        'acc=${UbxMga.accuracyMetersForAge(age)}m)',
      );
    } catch (e) {
      // ignore: avoid_print
      print('[GPS] Aiding inject failed: $e');
    }
  }

  void _rememberAidingFix(double lat, double lon, double altMeters) {
    _aidingLatitude = lat;
    _aidingLongitude = lon;
    _aidingAltitude = altMeters;
    _aidingSavedAt = DateTime.now();
    final last = _lastAidingPersistAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastAidingPersistAt = DateTime.now();
    unawaited(_saveSettings());
  }

  /// Manual disconnect pauses auto-connect until the next successful connect
  /// (or [resumeBleAutoConnect] from the device picker).
  Future<void> disconnect({bool userInitiated = true}) async {
    if (userInitiated) {
      _autoConnectSuppressed = true;
      _stopAutoConnectLoop();
      _stopReconnectLoop();
    }
    try {
      await _bleService.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    notifyListeners();
  }

  /// Re-enable background scan/connect after a manual disconnect / picker close.
  void resumeBleAutoConnect() {
    _autoConnectSuppressed = false;
    if (!_isConnected) {
      _startAutoConnectLoop();
    }
  }

  /// Pause background auto-connect while the device picker owns the scanner.
  void pauseBleAutoConnect() {
    _autoConnectSuppressed = false;
    _stopAutoConnectLoop();
  }

  void resetRace() {
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    notifyListeners();
  }

  // --- Local History Methods ---

  Future<void> loadSavedRuns() async {
    final hiveRuns = await _historyService.loadRuns();
    final durableMaps = await _durableStorage.pullSavedRuns();
    final byId = <String, SavedRun>{
      for (final r in hiveRuns) r.id: r,
    };
    for (final map in durableMaps) {
      try {
        final run = SavedRun.fromJson(map);
        byId.putIfAbsent(run.id, () => run);
      } catch (_) {}
    }
    _savedRuns = byId.values.toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    // Mirror any durable-only runs into Hive
    for (final run in _savedRuns) {
      if (!hiveRuns.any((h) => h.id == run.id)) {
        await _historyService.saveRun(run);
      }
    }
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
      unawaited(_durableStorage.pushSavedRunJson(runId, savedRun.toJson()));
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
        unawaited(
          _durableStorage.pushSavedRunJson(runId, updatedRun.toJson()),
        );
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
      unawaited(
        _durableStorage.pushSavedRunJson(id, updatedRun.toJson()),
      );
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
      unawaited(_releasePocketOrKeepAlive());
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
      await _syncPocketStatusNotification();
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
      await _releasePocketOrKeepAlive();
    } else {
      _isArmed = !_isArmed;
      if (_isArmed) {
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
      }
      if (_pocketMode) {
        await _syncPocketStatusNotification();
      } else {
        _applyScreenPolicy();
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
    if (_pocketMode) {
      await _syncPocketStatusNotification();
    }
    notifyListeners();
    return null;
  }

  void setLoggerTags(List<String> tags) {
    setLoggerTagsText(formatLoggerTags(tags));
  }

  void setLoggerTagsText(String value) {
    if (_loggerTagsText == value) return;
    _loggerTagsText = value;
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setLoggerNotes(String value) {
    if (_loggerNotes == value) return;
    _loggerNotes = value;
    unawaited(_saveSettings());
    notifyListeners();
  }

  void addLoggerTag(String tag) {
    final tags = parseLoggerTags(_loggerTagsText);
    if (tags.any((t) => t.toLowerCase() == tag.toLowerCase())) return;
    tags.add(tag);
    setLoggerTagsText(formatLoggerTags(tags));
  }

  Future<void> refreshLoggerTagIndex() async {
    await _durableStorage.pullRidesFromSaf();
    final manifests = await RideRecorder.listSessionManifests();
    final tagLists = <List<String>>[];
    for (final file in manifests) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        tagLists.add(RideRecorder.tagsFromManifest(map));
      } catch (_) {}
    }
    _rankedLoggerTags = rankTagsByFrequency(tagLists);
    notifyListeners();
  }

  /// Ordered startup: local cache, then durable OpenDragy/ overlay (settings included).
  Future<void> _bootstrapAppState() async {
    await _durableStorage.init();
    await _loadSettings();
    await _loadGarage();
    await loadSavedRuns();

    if (_durableStorage.hasDataFolder) {
      await _durableStorage.pullAllFromSaf();
      // Durable settings win (metric, pocket mode, targets, …).
      await _mergeSettingsFromDurable();
      await _loadGarageFromDurableIfPresent();
      await loadSavedRuns();
      // Keep durable copy in sync with anything only in Hive.
      await _pushSettingsToDurable();
      await _pushGarageToDurable();
    }

    await refreshLoggerTagIndex();
    _applyScreenPolicy();
    if (_pocketMode && !_isLoggerMode && !_isRideRecording) {
      await _syncPocketStatusNotification();
    }
    _listenBleAdapterAndAutoConnect();
    notifyListeners();
  }

  /// Prefer automatic `/storage/emulated/0/OpenDragy`; SAF picker as fallback.
  Future<bool> pickDurableDataFolder({bool allowSafFallback = true}) async {
    final ok = await _durableStorage.setupDataFolder(
      allowSafFallback: allowSafFallback,
    );
    if (!ok) return false;
    await _durableStorage.pullAllFromSaf();
    await loadSavedRuns();
    await _loadGarageFromDurableIfPresent();
    await _mergeSettingsFromDurable();
    await _pushGarageToDurable();
    await _pushSettingsToDurable();
    for (final run in _savedRuns) {
      await _durableStorage.pushSavedRunJson(run.id, run.toJson());
    }
    await refreshLoggerTagIndex();
    notifyListeners();
    return true;
  }

  Future<void> _loadGarageFromDurableIfPresent() async {
    final data = await _durableStorage.pullJsonFile('garage.json');
    if (data == null) return;
    try {
      final list = data['vehicles'] as List<dynamic>? ?? [];
      if (list.isEmpty && _vehicles.isNotEmpty) return;
      _vehicles = list
          .map((e) => Vehicle.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _activeVehicleId = data['activeVehicleId'] as String?;
      await _garageService.save(_vehicles, _activeVehicleId);
    } catch (_) {}
  }

  Future<void> _mergeSettingsFromDurable() async {
    final data = await _durableStorage.pullJsonFile('settings.json');
    if (data == null || data.isEmpty) return;
    _applySettingsMap(data);
    // Mirror into app-private settings.json for next cold start.
    await _settingsService.save(_settingsMap());
  }

  void _applySettingsMap(Map<String, dynamic> data) {
    if (data.containsKey('isMetric')) {
      _isMetric = data['isMetric'] as bool? ?? _isMetric;
    }
    if (data.containsKey('tempInCelsius')) {
      _tempInCelsius = data['tempInCelsius'] as bool? ?? _tempInCelsius;
    }
    if (data.containsKey('useNhraRules')) {
      _useNhraRules = data['useNhraRules'] as bool? ?? _useNhraRules;
    }
    if (data.containsKey('pocketMode')) {
      _pocketMode = data['pocketMode'] as bool? ?? _pocketMode;
    }
    if (data.containsKey('loggerTagsText') ||
        data.containsKey('loggerConfiguration')) {
      _loggerTagsText = data['loggerTagsText'] as String? ??
          data['loggerConfiguration'] as String? ??
          _loggerTagsText;
    }
    if (data.containsKey('loggerNotes')) {
      _loggerNotes = data['loggerNotes'] as String? ?? _loggerNotes;
    }
    if (data.containsKey('runMode')) {
      _runMode = data['runMode'] as String? ?? _runMode;
    }

    final dragTargetName = data['activeDragTarget'] as String?;
    if (dragTargetName != null) {
      _activeDragTarget = RaceDragTarget.values.firstWhere(
        (e) => e.name == dragTargetName,
        orElse: () => _activeDragTarget,
      );
    }
    final intervalTargetName = data['activeIntervalTarget'] as String?;
    if (intervalTargetName != null) {
      _activeIntervalTarget = RaceIntervalTarget.values.firstWhere(
        (e) => e.name == intervalTargetName,
        orElse: () => _activeIntervalTarget,
      );
    }
    if (data['customIntervalStartSpeed'] != null) {
      _customIntervalStartSpeed =
          (data['customIntervalStartSpeed'] as num).toDouble();
    }
    if (data['customIntervalEndSpeed'] != null) {
      _customIntervalEndSpeed =
          (data['customIntervalEndSpeed'] as num).toDouble();
    }
    _loadAidingFromMap(data);
    final lastBle = data['lastBleDeviceId'] as String?;
    if (lastBle != null && lastBle.isNotEmpty) {
      _bleReconnectId = lastBle;
    }
    _syncActiveTargetToUnit();
  }

  void _loadAidingFromMap(Map<String, dynamic> data) {
    final lat = (data['aidingLatitude'] as num?)?.toDouble();
    final lon = (data['aidingLongitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    _aidingLatitude = lat;
    _aidingLongitude = lon;
    _aidingAltitude = (data['aidingAltitude'] as num?)?.toDouble() ?? 0;
    final atMs = data['aidingSavedAtMs'] as int?;
    if (atMs != null) {
      _aidingSavedAt = DateTime.fromMillisecondsSinceEpoch(atMs);
    }
  }

  Future<void> _pushGarageToDurable() async {
    await _durableStorage.pushJsonFile('garage.json', {
      'vehicles': _vehicles.map((v) => v.toJson()).toList(),
      'activeVehicleId': _activeVehicleId,
    });
  }

  Future<void> _pushSettingsToDurable() async {
    await _durableStorage.pushJsonFile('settings.json', _settingsMap());
  }

  Map<String, dynamic> _settingsMap() => {
        'isMetric': _isMetric,
        'tempInCelsius': _tempInCelsius,
        'useNhraRules': _useNhraRules,
        'pocketMode': _pocketMode,
        'loggerTagsText': _loggerTagsText,
        'loggerNotes': _loggerNotes,
        'runMode': _runMode,
        'activeDragTarget': _activeDragTarget.name,
        'activeIntervalTarget': _activeIntervalTarget.name,
        'customIntervalStartSpeed': _customIntervalStartSpeed.round(),
        'customIntervalEndSpeed': _customIntervalEndSpeed.round(),
        if (_bleReconnectId != null) 'lastBleDeviceId': _bleReconnectId,
        if (_aidingLatitude != null) 'aidingLatitude': _aidingLatitude,
        if (_aidingLongitude != null) 'aidingLongitude': _aidingLongitude,
        if (_aidingLatitude != null) 'aidingAltitude': _aidingAltitude,
        if (_aidingSavedAt != null)
          'aidingSavedAtMs': _aidingSavedAt!.millisecondsSinceEpoch,
      };

  Future<String?> startRideRecording() async {
    if (_isRideRecording) return null;
    if (!_isConnected) {
      return 'Connect OpenDragy to start logging.';
    }

    await PocketForegroundService.requestPermissions();
    await _rideRecorder.start(
      vehicleName: activeVehicle?.displayName,
      vehicleId: activeVehicle?.id,
      tags: parseLoggerTags(_loggerTagsText),
      notes: _loggerNotes,
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
    final sessionId = _rideRecorder.sessionId;
    final file = await _rideRecorder.stop(
      vehicleName: activeVehicle?.displayName,
    );
    if (sessionId != null) {
      await _durableStorage.pushSessionFiles(sessionId);
    }
    await PocketForegroundService.stop();
    _isRideRecording = false;
    _applyScreenPolicy();
    if (_pocketMode && !_isLoggerMode) {
      await _syncPocketStatusNotification();
    }
    await refreshLoggerTagIndex();
    _needsUiUpdate = true;
    notifyListeners();
    return file;
  }

  void _startReconnectLoop() {
    // Kept for logger sessions — same path as auto-connect (last ID).
    if (!_isRideRecording || _bleReconnectId == null) return;
    _reconnectTimer?.cancel();
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

  void _listenBleAdapterAndAutoConnect() {
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on &&
          !_isConnected &&
          !_autoConnectSuppressed) {
        _startAutoConnectLoop();
      } else if (state != BluetoothAdapterState.on) {
        _stopAutoConnectLoop();
      }
    });
    if (!_isConnected && !_autoConnectSuppressed) {
      _startAutoConnectLoop();
    }
  }

  void _startAutoConnectLoop() {
    if (_autoConnectSuppressed || _isConnected) return;
    _autoConnectTimer?.cancel();
    // Immediate attempt, then retry while OpenDragy is away / BT warming up.
    unawaited(_tickAutoConnect());
    _autoConnectTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_tickAutoConnect());
    });
    if (_isRideRecording) {
      _startReconnectLoop();
    }
  }

  void _stopAutoConnectLoop() {
    _autoConnectTimer?.cancel();
    _autoConnectTimer = null;
  }

  Future<bool> _ensureBlePermissions() async {
    if (_blePermissionsGranted) return true;
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      _blePermissionsGranted = statuses.values.every((s) => s.isGranted);
    } catch (_) {
      _blePermissionsGranted = false;
    }
    return _blePermissionsGranted;
  }

  Future<void> _tickAutoConnect() async {
    if (_isConnected ||
        _autoConnectSuppressed ||
        _autoConnectBusy ||
        _isDisposed) {
      return;
    }
    _autoConnectBusy = true;
    try {
      if (!await _ensureBlePermissions()) {
        _stopAutoConnectLoop();
        return;
      }
      if (!await _bleService.isAdapterOn) return;

      // 1) Fast path: last known remote ID (works even with weak advertising).
      final lastId = _bleReconnectId;
      if (lastId != null && lastId.isNotEmpty) {
        // ignore: avoid_print
        print('[BLE] Auto-connect try lastId=$lastId');
        final ok = await connect(BluetoothDevice.fromId(lastId));
        if (ok || _isConnected) return;
      }

      // 2) Scan for advertised name "OpenDragy".
      // ignore: avoid_print
      print('[BLE] Auto-connect scanning for $_openDragyBleName…');
      final device = await _scanForOpenDragy(
        timeout: const Duration(seconds: 7),
      );
      if (device == null || _isConnected || _autoConnectSuppressed) return;
      // ignore: avoid_print
      print('[BLE] Auto-connect found ${device.platformName} '
          '${device.remoteId.str}');
      await connect(device);
    } catch (e) {
      // ignore: avoid_print
      print('[BLE] Auto-connect tick failed: $e');
    } finally {
      _autoConnectBusy = false;
    }
  }

  Future<BluetoothDevice?> _scanForOpenDragy({
    required Duration timeout,
  }) async {
    final completer = Completer<BluetoothDevice?>();
    late final StreamSubscription<List<ScanResult>> sub;
    sub = _bleService.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.trim();
        if (name.toLowerCase() == _openDragyBleName.toLowerCase() ||
            name.toLowerCase().contains('opendragy')) {
          if (!completer.isCompleted) completer.complete(r.device);
          return;
        }
      }
    });
    try {
      _bleService.startScan(
        withNames: [_openDragyBleName],
        timeout: timeout,
      );
      return await completer.future.timeout(
        timeout + const Duration(milliseconds: 800),
        onTimeout: () => null,
      );
    } finally {
      await sub.cancel();
      await _bleService.stopScan();
    }
  }

  Future<void> _updateLoggerNotification() async {
    if (!_isRideRecording) return;
    final status = _isConnected ? 'GPS live' : 'GPS paused';
    final pts = _rideRecorder.trackPointCount;
    final tags = parseLoggerTags(_loggerTagsText);
    final tagHint = tags.isEmpty ? '' : ' · ${tags.first}';
    await PocketForegroundService.update(
      title: 'OpenDragy — Logger',
      subtitle: '$status · $pts pts$tagHint',
      showStop: true,
      showDisarm: false,
    );
  }

  Future<void> _syncPocketStatusNotification() async {
    if (!_pocketMode || _isLoggerMode || _isRideRecording) return;
    await PocketForegroundService.requestPermissions();

    if (_metrics.isRunning) {
      await PocketForegroundService.startOrUpdate(
        title: 'OpenDragy — Running',
        subtitle:
            '$_pocketTargetLabel · ${_metrics.elapsedTime.toStringAsFixed(2)} s',
        showStop: true,
      );
      return;
    }
    if (_isArmed) {
      await PocketForegroundService.startOrUpdate(
        title: 'OpenDragy — Armed',
        subtitle: 'Target: $_pocketTargetLabel — screen may turn off',
        showDisarm: true,
      );
      return;
    }
    if (!_isConnected) {
      await PocketForegroundService.startOrUpdate(
        title: 'OpenDragy — Pocket',
        subtitle: 'Disconnected — connect OpenDragy',
      );
      return;
    }
    await PocketForegroundService.startOrUpdate(
      title: 'OpenDragy — Pocket',
      subtitle: 'Ready · $_pocketTargetLabel · $_satellites SAT',
    );
  }

  Future<void> _releasePocketOrKeepAlive() async {
    if (_isRideRecording) return;
    if (_pocketMode && !_isLoggerMode) {
      await _syncPocketStatusNotification();
    } else {
      await PocketForegroundService.stop();
    }
  }

  Future<void> _updatePocketRunningNotification() async {
    await _syncPocketStatusNotification();
  }

  Future<void> _finalizeCompletedRun(RaceMetrics metrics) async {
    await _saveRunToHistory(metrics);
    if (_pocketMode && !_isLoggerMode) {
      await PocketForegroundService.startOrUpdate(
        title: 'OpenDragy — Saved',
        subtitle:
            '${metrics.elapsedTime.toStringAsFixed(2)} s · $_pocketTargetLabel',
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!_metrics.isRunning) {
        await _syncPocketStatusNotification();
      }
      return;
    }
    if (!await PocketForegroundService.isRunning) return;
    await PocketForegroundService.update(
      title: 'OpenDragy — Saved',
      subtitle:
          '${metrics.elapsedTime.toStringAsFixed(2)} s · $_pocketTargetLabel',
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
      } else if (_pocketMode) {
        unawaited(_syncPocketStatusNotification());
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
    await _releasePocketOrKeepAlive();
    await PocketForegroundService.bringAppToForeground();
  }

  Future<void> _handlePocketDisarm() async {
    _isArmed = false;
    if (!_metrics.isRunning) {
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
    }
    notifyListeners();
    await _releasePocketOrKeepAlive();
    await PocketForegroundService.bringAppToForeground();
  }

  void setRunMode(String mode) {
    if (_runMode != mode) {
      _runMode = mode;
      _isArmed = false; // Disarm on mode change
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      unawaited(_releasePocketOrKeepAlive());
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
      unawaited(_releasePocketOrKeepAlive());
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
    unawaited(_releasePocketOrKeepAlive());
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final data = await _settingsService.load();
    _isMetric = data['isMetric'] as bool? ?? false;
    _tempInCelsius = data['tempInCelsius'] as bool? ?? true;
    _useNhraRules = data['useNhraRules'] as bool? ?? true;
    _pocketMode = data['pocketMode'] as bool? ?? false;
    _loggerTagsText = data['loggerTagsText'] as String? ??
        data['loggerConfiguration'] as String? ??
        '';
    _loggerNotes = data['loggerNotes'] as String? ?? '';
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
    _loadAidingFromMap(data);
    final lastBle = data['lastBleDeviceId'] as String?;
    if (lastBle != null && lastBle.isNotEmpty) {
      _bleReconnectId = lastBle;
    }
    _syncActiveTargetToUnit();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final map = _settingsMap();
    await _settingsService.save(map);
    unawaited(_pushSettingsToDurable());
  }

  // --- Garage Methods ---

  Future<void> _loadGarage() async {
    _vehicles = await _garageService.loadVehicles();
    _activeVehicleId = await _garageService.loadActiveVehicleId();
    notifyListeners();
  }

  Future<void> _saveGarage() async {
    await _garageService.save(_vehicles, _activeVehicleId);
    unawaited(_pushGarageToDurable());
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
    _isDisposed = true;
    FlutterForegroundTask.removeTaskDataCallback(_onPocketTaskData);
    _stopAutoConnectLoop();
    _stopReconnectLoop();
    _adapterStateSubscription?.cancel();
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


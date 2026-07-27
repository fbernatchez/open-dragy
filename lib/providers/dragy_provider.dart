import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
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
import '../services/milestone_audio_service.dart';
import '../services/media_arm_bridge.dart';
import '../models/app_cues.dart';
import '../utils/imu_gravity.dart';
import '../models/gps_pvt_sample.dart';
import '../models/raw_run_log.dart';
import '../utils/run_id.dart';
import '../models/run_trust.dart';
import '../models/imu_orientation.dart';
import '../models/satellite_sv.dart';

export '../models/app_cues.dart';
import '../utils/nmea_parser.dart';
import '../utils/odgp_parser.dart';
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

class DragyProvider extends ChangeNotifier with WidgetsBindingObserver {
  final BleService _bleService = BleService();
  final PhysicsEngine _physicsEngine = PhysicsEngine();
  final HistoryService _historyService = HistoryService();
  final GarageService _garageService = GarageService();
  final SettingsService _settingsService = SettingsService();
  final WeatherService _weatherService = WeatherService();
  final RideRecorder _rideRecorder = RideRecorder();
  final OpenDragyStorage _durableStorage = OpenDragyStorage();
  final MilestoneAudioService _milestoneAudio = MilestoneAudioService();
  final RunRawCapture _runRaw = RunRawCapture();

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

  /// Horizontal accuracy from NAV-PVT (metres). 0 = unknown / NMEA-only.
  double _hAccM = 0.0;
  double get hAccM => _hAccM;

  double _vAccM = 0.0;
  double get vAccM => _vAccM;

  /// Speed accuracy from NAV-PVT (m/s). 0 = unknown.
  double _sAccMps = 0.0;
  double get sAccMps => _sAccMps;

  bool _usedPvt = false;
  bool get usedPvt => _usedPvt;

  double _pdop = 0.0;
  double get pdop => _pdop;

  double _vdop = 0.0;
  double get vdop => _vdop;

  int? _fixQuality;
  int? get fixQuality => _fixQuality;

  int _fixType = 0;
  int get fixType => _fixType;

  int? _fixMode;
  int? get fixMode => _fixMode;

  /// Max sAcc (m/s) allowed to arm / treat GPS as ready (~1.8 km/h).
  static const double maxSAccReadyMps = 0.5;

  /// Soft ceiling: above this, block standing launch even if still "ready".
  static const double maxSAccLaunchMps = 0.75;

  /// Dragy-class gate: hAcc ≤ 5 m + sAcc ≤ 0.5 m/s + 3D; fallback HDOP ≤ 2.
  bool get isGpsReady {
    if (_satellites < 4) return false;
    if (_hAccM > 0) {
      if (_fixType < 3 || _hAccM > 5.0) return false;
      if (_sAccMps > 0 && _sAccMps > maxSAccReadyMps) return false;
      return true;
    }
    return _hdop > 0.0 && _hdop <= 2.0;
  }

  /// Standing-start allowed: ready GPS and speed accuracy not spiking.
  bool get allowStandingLaunch {
    if (!isGpsReady) return false;
    if (_sAccMps > 0 && _sAccMps > maxSAccLaunchMps) return false;
    return true;
  }

  /// Compact label for UI: ∞ until fix has a sane horizontal accuracy.
  String get hAccLabel {
    if (_fixType < 2 || _hAccM <= 0 || _hAccM > 99.9) return '∞';
    return '${_hAccM.toStringAsFixed(1)} m';
  }

  String get vAccLabel {
    if (_fixType < 2 || _vAccM <= 0 || _vAccM > 99.9) return '∞';
    return '${_vAccM.toStringAsFixed(1)} m';
  }

  String get sAccLabel {
    if (_fixType < 2 || _sAccMps <= 0 || _sAccMps > 99.9) return '∞';
    return '${(_sAccMps * 3.6).toStringAsFixed(1)} km/h';
  }

  /// When continuous 3D fix was acquired (null if no hold).
  DateTime? _fixHeldSince;
  DateTime? get fixHeldSince => _fixHeldSince;

  /// BLE connect / start of cold-ish search for this session.
  DateTime? _gpsSearchStartedAt;

  /// Time from connect → first 3D fix (frozen once acquired).
  Duration? _ttffDuration;
  Duration? get ttffDuration => _ttffDuration;

  /// Continuous 3D fix duration for GPS debug UI.
  Duration? get fixHoldDuration {
    final since = _fixHeldSince;
    if (since == null) return null;
    return DateTime.now().difference(since);
  }

  static String _formatGpsDuration(Duration d) {
    final totalSec = d.inSeconds;
    if (totalSec < 60) return '${totalSec}s';
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h ${rm}m';
  }

  String get fixAgeLabel {
    final d = fixHoldDuration;
    if (d == null) return '—';
    return _formatGpsDuration(d);
  }

  /// Time-to-first-fix after BLE connect; while searching shows live elapsed.
  String get ttffLabel {
    final done = _ttffDuration;
    if (done != null) return _formatGpsDuration(done);
    final start = _gpsSearchStartedAt;
    if (start == null || !_isConnected) return '—';
    return '${_formatGpsDuration(DateTime.now().difference(start))}…';
  }

  /// Axis along the car (default Y = original OpenDragy mount).
  ImuLongAxis _imuLongAxis = ImuLongAxis.y;
  ImuLongAxis get imuLongAxis => _imuLongAxis;

  /// Flip sign when the box is rotated 180° (accel shows as braking).
  bool _imuInvertLongitudinal = false;
  bool get imuInvertLongitudinal => _imuInvertLongitudinal;

  String get fixTypeLabel {
    switch (_fixType) {
      case 0:
        return 'No fix';
      case 1:
        return 'DR';
      case 2:
        return '2D';
      case 3:
        return '3D';
      case 4:
        return 'GNSS+DR';
      case 5:
        return 'Time';
      default:
        return 'Fix $_fixType';
    }
  }

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

  /// Spoken / beep cues at drag/interval milestones (helmet intercom).
  bool _voiceCuesEnabled = true;
  bool get voiceCuesEnabled => _voiceCuesEnabled;

  AudioCueMode _audioCueMode = AudioCueMode.voice;
  AudioCueMode get audioCueMode => _audioCueMode;

  /// Cue playback volume (0.3–1.0) for TTS / beeps → Bluetooth intercom.
  double _cueVolume = 1.0;
  double get cueVolume => _cueVolume;

  /// Cardo / AA media Next→ARM, Previous→DISARM.
  bool _headsetMediaArmEnabled = true;
  bool get headsetMediaArmEnabled => _headsetMediaArmEnabled;

  /// Last completed run summary for Android Auto (e.g. "1/8 7.81s @ 146").
  String? _lastCarResult;
  String? get lastCarResult => _lastCarResult;

  int _carFinishToken = 0;
  String _carFinishHeadline = '';
  List<String> _carFinishLines = const [];

  DateTime? _lastCarStatePush;

  /// Extra milestones beyond selected-target finish (default: 0–100 / 0–60).
  Set<OptionalAudioMilestone> _optionalAudioMilestones = {
    OptionalAudioMilestone.speedMark,
  };
  Set<OptionalAudioMilestone> get optionalAudioMilestones =>
      Set.unmodifiable(_optionalAudioMilestones);

  bool isOptionalAudioMilestoneEnabled(OptionalAudioMilestone m) =>
      _optionalAudioMilestones.contains(m);

  /// Finish flash / checkered flag — only when app is foreground (display on).
  FinishCelebrationMode _finishCelebration = FinishCelebrationMode.checkered;
  FinishCelebrationMode get finishCelebration => _finishCelebration;

  int _finishCelebrationToken = 0;
  int get finishCelebrationToken => _finishCelebrationToken;

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
  bool _appInForeground = true;
  static const Duration _autoConnectFgPeriod = Duration(seconds: 3);
  static const Duration _autoConnectBgPeriod = Duration(seconds: 10);
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

  /// Slow drift correction on longitudinal G while disarmed (pre-ARM fallback).
  double _idleLongitudinalOffset = 0.0;
  /// Gravity vector captured during ARM (~0.5 s stationary window).
  GravityVector? _gravityRef;
  bool _armCalibPending = false;
  DateTime? _armCalibStartedAt;
  final List<GravityVector> _armCalibSamples = [];
  static const Duration _armCalibDuration = Duration(milliseconds: 500);
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
  StreamSubscription? _odgpSubscription;
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

  /// Current drag / interval target label (for settings / notifications).
  String get activeTargetLabel => _pocketTargetLabel;

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      _needsUiUpdate = true;
    } catch (_) {}
  }

  DragyProvider() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapAppState());
    _loadAppVersion();
    _wireMediaArmBridge();

    FlutterForegroundTask.addTaskDataCallback(_onPocketTaskData);

    _uiTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final dirty = _needsUiUpdate || _metrics.isRunning || _isArmed;
      if (_needsUiUpdate || _metrics.isRunning) {
        notifyListeners();
        _needsUiUpdate = false;
      }
      if (dirty) {
        _pushCarStateThrottled();
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
        _fixHeldSince = null;
        _gpsSearchStartedAt = null;
        _ttffDuration = null;
        if (!_isRideRecording) {
          _isArmed = false;
          _cancelArmCalibration();
          _runRaw.clear();
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
        _gpsSearchStartedAt = DateTime.now();
        _ttffDuration = null;
        _fixHeldSince = null;
        _applyScreenPolicy();
        if (_satelliteDetailActive) {
          unawaited(_sendSatelliteDetailConfig(enable: true));
        }
        if (_isRideRecording) {
          unawaited(_updateLoggerNotification());
        } else {
          unawaited(_syncPocketStatusNotification());
        }
      }
      _needsUiUpdate = true;
    });

    _odgpSubscription = _bleService.odgpStream.listen(_onOdgpFix);

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
          _captureRawGpsIfArmed(
            GpsPvtSample(
              speedKmh: data.speedKmh!,
              latitude: data.latitude ?? _latitude,
              longitude: data.longitude ?? _longitude,
              altitudeM: data.altitude ?? _altitude,
              satellites: _satellites > 0 ? _satellites : null,
              hdop: _hdop > 0 ? _hdop : null,
              fixType: _fixQuality,
              usedPvt: false,
            ),
          );
          _applySpeedSample(
            speedKmh: data.speedKmh!,
            gpsTimeSeconds: data.timeSeconds,
          );
          updated = true;
        }

        // NMEA fallback: treat quality ≥ 1 + sats as a held fix.
        final q = data.fixQuality ?? _fixQuality ?? 0;
        final sats = data.satellites ?? _satellites;
        if (data.fixQuality != null || data.satellites != null) {
          _updateFixHold(q >= 1 && sats >= 4);
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
              fixType: _fixQuality,
              usedPvt: false,
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
          // BMI160 ±8g → 4096 LSB/g (ACCEL_RANGE 0x08).
          final ax = int.parse(parts[0].trim()) / 4096.0;
          final ay = int.parse(parts[1].trim()) / 4096.0;
          final az = int.parse(parts[2].trim()) / 4096.0;

          if (_armCalibPending) {
            _armCalibSamples.add(GravityVector(ax, ay, az));
            final started = _armCalibStartedAt;
            if (started != null &&
                DateTime.now().difference(started) >= _armCalibDuration) {
              _finishArmCalibration();
            }
          }

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

          final linear = LinearAcceleration.fromRaw(
            ax: ax,
            ay: ay,
            az: az,
            gravity: _gravityRef,
          );
          // Mount remap: pick long axis + optional invert (Settings → Hardware).
          double gForce = longitudinalG(
            ax: linear.x,
            ay: linear.y,
            az: linear.z,
            axis: _imuLongAxis,
            invert: _imuInvertLongitudinal,
          );

          // Slow EMA only when idle and gravity ref not yet established.
          if (_gravityRef == null &&
              !_metrics.isRunning &&
              !_isArmed &&
              !_armCalibPending &&
              isSpeedConstant) {
            const double alpha = 0.02;
            _idleLongitudinalOffset =
                _idleLongitudinalOffset * (1.0 - alpha) + gForce * alpha;
          }

          final longitudinalOffset =
              _gravityRef != null ? 0.0 : _idleLongitudinalOffset;
          double calibratedGForce = gForce - longitudinalOffset;

          // Clamp noise to prevent "-0.0" from showing up
          if (calibratedGForce.abs() < 0.05) {
            calibratedGForce = 0.0;
          }

          if (_runRaw.isActive) {
            _runRaw.addImu(axG: ax, ayG: ay, azG: az);
          }

          _metrics = _metrics.copyWith(gForce: calibratedGForce);
          _needsUiUpdate = true;
        }
      } catch (e) {
        // Ignore parsing errors for individual frames
      }
    });
  }

  void _onOdgpFix(OdgpFix fix) {
    // ignore: avoid_print
    print(
      '[GPS] ODGP sv=${fix.numSV} fix=${fix.fixType} '
      'hAcc=${fix.hAccM.toStringAsFixed(2)}m '
      'sAcc=${fix.sAccMps.toStringAsFixed(2)}m/s '
      'pvt=${fix.usedPvt} '
      'spd=${fix.speedKmh.toStringAsFixed(1)}',
    );
    _satellites = fix.numSV;
    _fixType = fix.fixType;
    _fixQuality = fix.fixType;
    _fixMode = fix.fixType >= 3 ? 3 : (fix.fixType >= 2 ? 2 : 1);
    _hAccM = fix.hAccM;
    _vAccM = fix.vAccM;
    _sAccMps = fix.sAccMps;
    _usedPvt = fix.usedPvt;
    _hdop = fix.hdopApprox;
    _altitude = fix.altitudeM;
    _updateFixHold(
      fix.valid && fix.fixType >= 3 && fix.numSV >= 4,
    );
    if (fix.valid) {
      _latitude = fix.latitude;
      _longitude = fix.longitude;
      _rememberAidingFix(fix.latitude, fix.longitude, fix.altitudeM);
    }

    if (fix.valid || fix.speedKmh >= 0) {
      _captureRawGpsIfArmed(
        GpsPvtSample.fromOdgp(
          fix,
          hdopApprox: _hdop > 0 ? _hdop : null,
        ),
      );
      _applySpeedSample(
        speedKmh: fix.speedKmh.clamp(0.0, 500.0),
        gpsTimeSeconds: fix.timeSeconds,
        gpsTimeMs: fix.iTOW,
      );
    }

    if (_isRideRecording && _latitude != null && _longitude != null) {
      unawaited(
        _rideRecorder.appendTrackPoint(
          latitude: _latitude!,
          longitude: _longitude!,
          altitudeMeters: _altitude,
          speedKmh: fix.speedKmh,
        ),
      );
      unawaited(
        _rideRecorder.appendGpsRow(
          latitude: _latitude!,
          longitude: _longitude!,
          altitudeMeters: _altitude,
          speedKmh: fix.speedKmh,
          iTowMs: fix.iTOW,
          hAccMeters: fix.hAccM,
          vAccMeters: fix.vAccM,
          sAccMps: fix.sAccMps,
          fixType: fix.fixType,
          headingDeg: fix.headingDeg,
          hdop: _hdop > 0 ? _hdop : null,
          satellites: fix.numSV,
          usedPvt: true,
        ),
      );
      if (_rideRecorder.trackPointCount % 25 == 0) {
        unawaited(_updateLoggerNotification());
      }
    }

    _needsUiUpdate = true;
  }

  void _captureRawGpsIfArmed(GpsPvtSample sample) {
    if (_runRaw.isActive) {
      _runRaw.addGpsPvt(sample);
    }
  }

  void _applySpeedSample({
    required double speedKmh,
    double? gpsTimeSeconds,
    int? gpsTimeMs,
  }) {
    _recentSpeeds.add(speedKmh);
    if (_recentSpeeds.length > 5) {
      _recentSpeeds.removeAt(0);
    }

    final wasRunning = _metrics.isRunning;
    final previousMetrics = _metrics;

    _metrics = _physicsEngine.updateMetrics(
      _metrics,
      speedKmh,
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
      gpsTimeSeconds: gpsTimeSeconds,
      gpsTimeMs: gpsTimeMs,
      sAccMps: _sAccMps > 0 ? _sAccMps : null,
      allowStandingLaunch: allowStandingLaunch,
    );
    final isRunning = _metrics.isRunning;

    if (!_isLoggerMode && _voiceCuesEnabled) {
      _milestoneAudio.onMetricsUpdate(
        previous: previousMetrics,
        next: _metrics,
        isMetric: _isMetric,
        targetMilestoneId: _runMode == 'drag'
            ? _audioMilestoneIdForDragTarget(_activeDragTarget)
            : null,
        enabledOptionalIds:
            _optionalAudioMilestones.map((e) => e.id).toSet(),
      );
    }

    if (!wasRunning && isRunning) {
      if (_armCalibPending) {
        _finishArmCalibration();
      }
      _runRaw.markRunStarted();
    }

    if (wasRunning &&
        !isRunning &&
        _metrics.history.isNotEmpty &&
        !_isLoggerMode) {
      _maybeTriggerFinishCelebration();
    }

    if (isRunning) {
      _lastGpsUpdateTime = DateTime.now();
      final now = DateTime.now();
      if (_lastPocketNotifyAt == null ||
          now.difference(_lastPocketNotifyAt!) > const Duration(seconds: 1)) {
        _lastPocketNotifyAt = now;
        unawaited(_updatePocketRunningNotification());
      }
    } else {
      _lastGpsUpdateTime = null;
      if (wasRunning) {
        _isArmed = false;
      }
    }

    if (wasRunning && !isRunning && _metrics.history.isNotEmpty) {
      unawaited(_finalizeCompletedRun(_metrics));
    } else if (!wasRunning && isRunning) {
      unawaited(_updatePocketRunningNotification());
    }
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

  /// Speeds up M10 cold start: tight phone UTC + phone/last-known position.
  Future<void> _injectGpsAiding() async {
    try {
      // ~1 s trusted UTC from the phone (NTP-disciplined).
      final timeMsg = UbxMga.timeUtc(
        DateTime.now().toUtc(),
        accuracySeconds: 1,
        trustedSource: true,
      );
      await _bleService.writeToGps(timeMsg);
      await Future.delayed(const Duration(milliseconds: 40));

      final phone = await _tryPhoneAidingPosition();
      if (phone != null) {
        final acc = UbxMga.phoneAccuracyMeters(phone.accuracy);
        final posMsg = UbxMga.posLlh(
          latitudeDeg: phone.latitude,
          longitudeDeg: phone.longitude,
          altitudeMeters: phone.altitude.isFinite ? phone.altitude : 0,
          posAccMeters: acc,
        );
        await _bleService.writeToGps(posMsg);
        _rememberAidingFix(
          phone.latitude,
          phone.longitude,
          phone.altitude.isFinite ? phone.altitude : 0,
        );
        // ignore: avoid_print
        print(
          '[GPS] Aiding injected (time + phone pos '
          'acc=${acc.toStringAsFixed(0)}m)',
        );
        return;
      }

      // Fallback: last OpenDragy fix stored on the phone.
      final lat = _aidingLatitude;
      final lon = _aidingLongitude;
      final savedAt = _aidingSavedAt;
      if (lat == null || lon == null || savedAt == null) {
        // ignore: avoid_print
        print('[GPS] Aiding: time only (no phone/saved position)');
        return;
      }

      final age = DateTime.now().difference(savedAt);
      if (age.inDays > 30) {
        // ignore: avoid_print
        print('[GPS] Aiding: time only (saved pos too old)');
        return;
      }

      final acc = UbxMga.accuracyMetersForAge(age);
      final posMsg = UbxMga.posLlh(
        latitudeDeg: lat,
        longitudeDeg: lon,
        altitudeMeters: _aidingAltitude,
        posAccMeters: acc,
      );
      await _bleService.writeToGps(posMsg);
      // ignore: avoid_print
      print(
        '[GPS] Aiding injected (time + saved pos age=${age.inHours}h '
        'acc=${acc.toStringAsFixed(0)}m)',
      );
    } catch (e) {
      // ignore: avoid_print
      print('[GPS] Aiding inject failed: $e');
    }
  }

  /// Best-effort phone GNSS/network fix for MGA-INI-POS (few seconds max).
  Future<Position?> _tryPhoneAidingPosition() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Prefer a fresh reading; fall back to last known if timeout.
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } on TimeoutException {
        return Geolocator.getLastKnownPosition();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[GPS] Phone position for aiding failed: $e');
      return null;
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
    _pushCarStateThrottled(force: true);
  }

  Future<void> _saveRunToHistory(RaceMetrics runMetrics) async {
    final duration = runMetrics.elapsedTime;
    final maxSpeed = runMetrics.history.isNotEmpty
        ? runMetrics.history.map((e) => e.speedKmh).reduce(max)
        : 0.0;

    // Filter out creeping / GPS wander blips
    if (duration >= 1.0 && maxSpeed >= 10.0) {
      final vehicle = activeVehicle;
      final runAt = DateTime.now();
      final runId = RunId.allocate(
        runAt,
        _savedRuns.map((r) => r.id),
      );

      final rawGps = List<RawGpsSample>.from(_runRaw.gps);
      final rawImu = List<RawImuSample>.from(_runRaw.imu);
      final rawStartMs = _runRaw.runStartElapsedMs;
      final gpsCsv = _runRaw.toGpsCsv();
      final imuCsv = _runRaw.toImuCsv();

      final trust = RunTrust.fromRawGps(
        rawGps.isEmpty ? null : rawGps,
        runStartElapsedMs: rawStartMs,
      );

      final savedRun = SavedRun(
        id: runId,
        dateTime: runAt,
        metrics: runMetrics,
        temperature: null,
        humidity: null,
        vehicleId: vehicle?.id,
        vehicleName: vehicle?.displayName,
        rawGps: rawGps.isEmpty ? null : rawGps,
        rawImu: rawImu.isEmpty ? null : rawImu,
        rawRunStartElapsedMs: rawStartMs,
        trust: trust,
      );

      // Save run locally and show in UI immediately
      await _historyService.saveRun(savedRun);
      unawaited(_durableStorage.pushSavedRunJson(runId, savedRun.toJson()));
      if (rawGps.isNotEmpty || rawImu.isNotEmpty) {
        unawaited(
          _durableStorage.pushSavedRunRawCsv(
            runId: runId,
            gpsCsv: gpsCsv,
            imuCsv: imuCsv,
          ),
        );
      }
      _savedRuns.insert(0, savedRun);
      _lastCarResult = _formatCarResult(savedRun);
      _carFinishHeadline = _lastCarResult ?? 'Run complete';
      _carFinishLines = _carMetricLines(savedRun);
      _carFinishToken++;
      unawaited(_saveSettings());
      _needsUiUpdate = true;
      notifyListeners();
      _pushCarStateThrottled(force: true);

      // Fetch weather asynchronously in the background if coordinates are available
      final lat = _latitude;
      final lon = _longitude;
      if (lat != null && lon != null && (lat != 0.0 || lon != 0.0)) {
        _fetchAndApplyWeather(runId, lat, lon);
      }
    }
    _runRaw.clear();
  }

  String _formatCarResult(SavedRun run) {
    final m = run.metrics;
    final label = activeTargetLabel;
    double? t;
    double? trap;
    if (_runMode == 'drag') {
      switch (_activeDragTarget) {
        case RaceDragTarget.sixtyFeet:
          t = m.time60ft;
          break;
        case RaceDragTarget.threeHundredThirtyFeet:
          t = m.time330ft;
          break;
        case RaceDragTarget.eighthMile:
          t = m.time18Mile;
          trap = m.trap18Mile;
          break;
        case RaceDragTarget.thousandFeet:
          t = m.time1000ft;
          trap = m.trap1000ft;
          break;
        case RaceDragTarget.quarterMile:
          t = m.time14Mile;
          trap = m.trap14Mile;
          break;
        case RaceDragTarget.halfMile:
          t = m.time12Mile;
          trap = m.trap12Mile;
          break;
      }
    } else {
      t = m.time0to100kmh ?? m.time0to60mph;
    }
    if (t == null) return '$label done';
    if (trap != null) {
      return '$label ${t.toStringAsFixed(2)}s @ ${trap.toStringAsFixed(0)}';
    }
    return '$label ${t.toStringAsFixed(2)}s';
  }

  /// AA rows as "Label|value" (split on native side).
  List<String> _carMetricLines(SavedRun run) {
    final m = run.metrics;
    final nhra = _useNhraRules && m.rolloutTime1ft != null;
    String? fmt(double? t) => t == null ? null : '${t.toStringAsFixed(3)} s';
    String? trap(double? v) =>
        v == null ? null : '${v.toStringAsFixed(1)} km/h';

    final lines = <String>[];
    void add(String label, String? value) {
      if (value != null) lines.add('$label|$value');
    }

    if (nhra) {
      add('60 ft (1 ft)', fmt(m.time60ftRollout ?? m.time60ft));
      add('330 ft', fmt(m.time330ftRollout ?? m.time330ft));
      add('0–60 mph', fmt(m.time0to60mphRollout ?? m.time0to60mph));
      add('0–100 km/h', fmt(m.time0to100kmhRollout ?? m.time0to100kmh));
      add('1/8 mile', fmt(m.time18MileRollout ?? m.time18Mile));
      add('1/8 trap', trap(m.trap18Mile));
      add('1000 ft', fmt(m.time1000ftRollout ?? m.time1000ft));
      add('1/4 mile', fmt(m.time14MileRollout ?? m.time14Mile));
      add('1/4 trap', trap(m.trap14Mile));
      add('1/2 mile', fmt(m.time12MileRollout ?? m.time12Mile));
    } else {
      add('60 ft', fmt(m.time60ft));
      add('330 ft', fmt(m.time330ft));
      add('0–60 mph', fmt(m.time0to60mph));
      add('0–100 km/h', fmt(m.time0to100kmh));
      add('1/8 mile', fmt(m.time18Mile));
      add('1/8 trap', trap(m.trap18Mile));
      add('1000 ft', fmt(m.time1000ft));
      add('1000 trap', trap(m.trap1000ft));
      add('1/4 mile', fmt(m.time14Mile));
      add('1/4 trap', trap(m.trap14Mile));
      add('1/2 mile', fmt(m.time12Mile));
      add('1/2 trap', trap(m.trap12Mile));
    }
    add('0–200 km/h', fmt(m.time0to200kmh));
    add('100–200 km/h', fmt(m.time100to200kmh));
    add('Vmax', trap(m.history.isEmpty
        ? null
        : m.history.map((e) => e.speedKmh).reduce(max)));
    if (run.vehicleName != null && run.vehicleName!.trim().isNotEmpty) {
      add('Vehicle', run.vehicleName!.trim());
    }
    return lines;
  }

  /// History title from the run itself (not the currently selected AA target).
  String _carHistoryTitle(SavedRun run) {
    final m = run.metrics;
    String pair(String label, double? t, [double? trap]) {
      if (t == null) return '';
      if (trap != null) {
        return '$label ${t.toStringAsFixed(2)}s @ ${trap.toStringAsFixed(0)}';
      }
      return '$label ${t.toStringAsFixed(2)}s';
    }

    for (final s in [
      pair('1/4', m.time14Mile, m.trap14Mile),
      pair('1/8', m.time18Mile, m.trap18Mile),
      pair('0–100', m.time0to100kmh),
      pair('0–60', m.time0to60mph),
      pair('60 ft', m.time60ft),
      pair('1/2', m.time12Mile, m.trap12Mile),
    ]) {
      if (s.isNotEmpty) return s;
    }
    return 'Run';
  }

  List<Map<String, dynamic>> _carHistoryPayload({int limit = 12}) {
    return [
      for (final run in _savedRuns.take(limit))
        {
          'id': run.id,
          'title': _carHistoryTitle(run),
          'subtitle':
              '${_formatCarHistoryTime(run.dateTime)}'
              '${run.vehicleName != null ? ' · ${run.vehicleName}' : ''}',
          'lines': _carMetricLines(run),
        },
    ];
  }

  String _formatCarHistoryTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
    await _durableStorage.deleteSavedRunFiles(id);
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
      _runMode = 'drag';
      _isArmed = false; // Disarm on target change
      _cancelArmCalibration();
      _runRaw.clear();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      unawaited(_releasePocketOrKeepAlive());
      _saveSettings();
      notifyListeners();
      _pushCarStateThrottled(force: true);
    }
  }

  /// Android Auto / headset: set drag target by enum name.
  void setDragTargetFromCar(String name) {
    if (_metrics.isRunning) return;
    for (final t in RaceDragTarget.values) {
      if (t.name == name) {
        setActiveDragTarget(t);
        return;
      }
    }
  }

  /// Android Auto: cycle 60ft → … → 1/2 mile → 60ft.
  void cycleDragTargetFromCar() {
    if (_metrics.isRunning) return;
    final values = RaceDragTarget.values;
    final idx = values.indexOf(_activeDragTarget);
    final next = values[(idx + 1) % values.length];
    setActiveDragTarget(next);
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

  void setImuLongAxis(ImuLongAxis axis) {
    if (_imuLongAxis == axis) return;
    _imuLongAxis = axis;
    _idleLongitudinalOffset = 0.0;
    _cancelArmCalibration();
    _saveSettings();
    notifyListeners();
  }

  void setImuInvertLongitudinal(bool invert) {
    if (_imuInvertLongitudinal == invert) return;
    _imuInvertLongitudinal = invert;
    _idleLongitudinalOffset = 0.0;
    _cancelArmCalibration();
    _saveSettings();
    notifyListeners();
  }

  void _updateFixHold(bool holding) {
    if (holding) {
      final now = DateTime.now();
      if (_ttffDuration == null && _gpsSearchStartedAt != null) {
        _ttffDuration = now.difference(_gpsSearchStartedAt!);
      }
      _fixHeldSince ??= now;
    } else if (_fixHeldSince != null) {
      _fixHeldSince = null;
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

  void setVoiceCuesEnabled(bool value) {
    if (_voiceCuesEnabled == value) return;
    _voiceCuesEnabled = value;
    _milestoneAudio.setEnabled(value);
    _saveSettings();
    notifyListeners();
  }

  void setAudioCueMode(AudioCueMode mode) {
    if (_audioCueMode == mode) return;
    _audioCueMode = mode;
    _milestoneAudio.setMode(mode);
    _saveSettings();
    notifyListeners();
  }

  void setCueVolume(double value) {
    final v = value.clamp(0.3, 1.0);
    if ((v - _cueVolume).abs() < 0.001) return;
    _cueVolume = v;
    _milestoneAudio.setVolume(_cueVolume);
    _saveSettings();
    notifyListeners();
  }

  void setHeadsetMediaArmEnabled(bool value) {
    if (_headsetMediaArmEnabled == value) return;
    _headsetMediaArmEnabled = value;
    unawaited(MediaArmBridge.instance.setEnabled(value));
    _saveSettings();
    notifyListeners();
    if (value) _pushCarStateThrottled(force: true);
  }

  void _wireMediaArmBridge() {
    final bridge = MediaArmBridge.instance;
    bridge.ensureListening();
    bridge.onNext = () => unawaited(toggleArmFromHeadset());
    bridge.onPrevious = () => unawaited(disarmFromHeadset());
    bridge.onSetDragTarget = (name) => setDragTargetFromCar(name);
    bridge.onCycleDragTarget = () => cycleDragTargetFromCar();
    bridge.onSetVehicle = (id) => unawaited(setVehicleFromCar(id));
  }

  void _pushCarStateThrottled({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastCarStatePush != null &&
        now.difference(_lastCarStatePush!) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastCarStatePush = now;
    unawaited(
      MediaArmBridge.instance.updatePlaybackState(
        armed: _isArmed,
        running: _metrics.isRunning,
        speedKmh: _metrics.speedKmh,
        targetLabel: activeTargetLabel,
        dragTargetName: _activeDragTarget.name,
        dragTargets: [
          for (final t in RaceDragTarget.values)
            {'name': t.name, 'label': t.label},
        ],
        lastResult: _lastCarResult,
        finishToken: _carFinishToken,
        finishHeadline: _carFinishHeadline,
        finishLines: _carFinishLines,
        history: _carHistoryPayload(),
        vehicleId: _activeVehicleId ?? '',
        vehicleLabel: activeVehicle?.displayName ?? '—',
        vehicles: [
          for (final v in _vehicles) {'id': v.id, 'label': v.displayName},
        ],
      ),
    );
  }

  Future<void> setVehicleFromCar(String id) async {
    if (_metrics.isRunning) return;
    if (!_vehicles.any((v) => v.id == id)) return;
    await setActiveVehicle(id);
  }

  /// Cardo / AA Next Track — toggle ARM and announce to helmet.
  Future<void> toggleArmFromHeadset() async {
    if (!_headsetMediaArmEnabled) return;
    if (_isLoggerMode) return;
    if (_metrics.isRunning) return;

    final wasArmed = _isArmed;
    await toggleArm();
    if (_isArmed && !wasArmed) {
      unawaited(_milestoneAudio.announceArmed());
    } else if (!_isArmed && wasArmed) {
      unawaited(_milestoneAudio.announceDisarmed());
    }
    _pushCarStateThrottled(force: true);
  }

  /// Cardo / AA Previous Track — DISARM only.
  Future<void> disarmFromHeadset() async {
    if (!_headsetMediaArmEnabled) return;
    if (_isLoggerMode) return;
    if (_metrics.isRunning) return;
    if (!_isArmed) return;
    await toggleArm();
    if (!_isArmed) {
      unawaited(_milestoneAudio.announceDisarmed());
    }
    _pushCarStateThrottled(force: true);
  }

  void setOptionalAudioMilestone(OptionalAudioMilestone m, bool enabled) {
    final next = Set<OptionalAudioMilestone>.from(_optionalAudioMilestones);
    if (enabled) {
      next.add(m);
    } else {
      next.remove(m);
    }
    if (next.length == _optionalAudioMilestones.length &&
        next.containsAll(_optionalAudioMilestones)) {
      return;
    }
    _optionalAudioMilestones = next;
    _saveSettings();
    notifyListeners();
  }

  /// Play one sample of the current cue style (headphones / intercom check).
  Future<void> playTestAudioCue() => _milestoneAudio.playTestCue();

  static String _audioMilestoneIdForDragTarget(RaceDragTarget target) {
    switch (target) {
      case RaceDragTarget.sixtyFeet:
        return '60ft';
      case RaceDragTarget.threeHundredThirtyFeet:
        return '330ft';
      case RaceDragTarget.eighthMile:
        return '18mile';
      case RaceDragTarget.thousandFeet:
        return '1000ft';
      case RaceDragTarget.quarterMile:
        return '14mile';
      case RaceDragTarget.halfMile:
        return '12mile';
    }
  }

  void setFinishCelebration(FinishCelebrationMode mode) {
    if (_finishCelebration == mode) return;
    _finishCelebration = mode;
    _saveSettings();
    notifyListeners();
  }

  void _maybeTriggerFinishCelebration() {
    if (_finishCelebration == FinishCelebrationMode.off) return;
    // Pocket / screen-off: app leaves resumed — skip overlay.
    if (!_appInForeground) return;
    _finishCelebrationToken++;
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

  /// Start collecting IMU for [_armCalibDuration] after ARM (staged zero).
  void _beginArmCalibration() {
    _armCalibPending = true;
    _armCalibStartedAt = DateTime.now();
    _armCalibSamples.clear();
    _gravityRef = null;
    _idleLongitudinalOffset = 0.0;
  }

  void _cancelArmCalibration() {
    _armCalibPending = false;
    _armCalibStartedAt = null;
    _armCalibSamples.clear();
    _gravityRef = null;
  }

  /// Average the post-ARM window → freeze gravity vector for subtraction.
  void _finishArmCalibration() {
    final gravity = GravityVector.average(_armCalibSamples);
    if (gravity == null) {
      _cancelArmCalibration();
      return;
    }
    _gravityRef = gravity;
    _idleLongitudinalOffset = 0.0;
    _armCalibPending = false;
    _armCalibStartedAt = null;
    _armCalibSamples.clear();
  }

  /// Returns an error message when arming is blocked; null on success.
  Future<String?> toggleArm() async {
    if (_isLoggerMode) return null;
    if (_metrics.isRunning) {
      _isArmed = false;
      _cancelArmCalibration();
      _runRaw.clear();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      await _releasePocketOrKeepAlive();
    } else {
      if (!_isArmed && !isGpsReady) {
        notifyListeners();
        return 'Waiting for GPS (hAcc ≤ 5 m, sAcc ≤ 0.5 m/s)';
      }
      _isArmed = !_isArmed;
      if (_isArmed) {
        _metrics = _physicsEngine.reset();
        _lastGpsUpdateTime = null;
        _beginArmCalibration();
        _runRaw.startArmed();
      } else {
        _cancelArmCalibration();
        _runRaw.clear();
      }
      if (_pocketMode) {
        await _syncPocketStatusNotification();
      } else {
        _applyScreenPolicy();
        await PocketForegroundService.stop();
      }
    }
    notifyListeners();
    _pushCarStateThrottled(force: true);
    return null;
  }

  Future<String?> setLoggerMode(bool enabled) async {
    if (_isLoggerMode == enabled) return null;

    if (enabled) {
      _isLoggerMode = true;
      _isArmed = false;
      _cancelArmCalibration();
      _runRaw.clear();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      _milestoneAudio.resetRun();
      await PocketForegroundService.stop();
      notifyListeners();
      // Recording starts only via Start — tags/notes stay editable until then.
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
    unawaited(_milestoneAudio.init());
    _milestoneAudio.setEnabled(_voiceCuesEnabled);
    _milestoneAudio.setMode(_audioCueMode);
    _milestoneAudio.setVolume(_cueVolume);
    await MediaArmBridge.instance.setEnabled(_headsetMediaArmEnabled);
    _pushCarStateThrottled(force: true);
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
    if (data.containsKey('voiceCuesEnabled')) {
      _voiceCuesEnabled = data['voiceCuesEnabled'] as bool? ?? _voiceCuesEnabled;
      _milestoneAudio.setEnabled(_voiceCuesEnabled);
    }
    final audioCueName = data['audioCueMode'] as String?;
    if (audioCueName != null) {
      _audioCueMode = AudioCueMode.values.firstWhere(
        (e) => e.name == audioCueName,
        orElse: () => _audioCueMode,
      );
      _milestoneAudio.setMode(_audioCueMode);
    }
    if (data.containsKey('cueVolume')) {
      _cueVolume = ((data['cueVolume'] as num?)?.toDouble() ?? _cueVolume)
          .clamp(0.3, 1.0);
      _milestoneAudio.setVolume(_cueVolume);
    }
    if (data.containsKey('headsetMediaArmEnabled')) {
      _headsetMediaArmEnabled =
          data['headsetMediaArmEnabled'] as bool? ?? _headsetMediaArmEnabled;
    }
    if (data.containsKey('lastCarResult')) {
      _lastCarResult = data['lastCarResult'] as String? ?? _lastCarResult;
    }
    final optionalRaw = data['optionalAudioMilestones'];
    if (optionalRaw is List) {
      final parsed = <OptionalAudioMilestone>{};
      for (final item in optionalRaw) {
        final name = item.toString();
        for (final m in OptionalAudioMilestone.values) {
          if (m.name == name || m.id == name) {
            parsed.add(m);
            break;
          }
        }
      }
      _optionalAudioMilestones = parsed;
    }
    final finishName = data['finishCelebration'] as String?;
    if (finishName != null) {
      _finishCelebration = FinishCelebrationMode.values.firstWhere(
        (e) => e.name == finishName,
        orElse: () => _finishCelebration,
      );
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
    final longAxisName = data['imuLongAxis'] as String?;
    if (longAxisName != null) {
      _imuLongAxis = ImuLongAxis.values.firstWhere(
        (e) => e.name == longAxisName,
        orElse: () => _imuLongAxis,
      );
    }
    if (data.containsKey('imuInvertLongitudinal')) {
      _imuInvertLongitudinal =
          data['imuInvertLongitudinal'] as bool? ?? _imuInvertLongitudinal;
    }
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
        'voiceCuesEnabled': _voiceCuesEnabled,
        'audioCueMode': _audioCueMode.name,
        'cueVolume': _cueVolume,
        'headsetMediaArmEnabled': _headsetMediaArmEnabled,
        if (_lastCarResult != null) 'lastCarResult': _lastCarResult,
        'optionalAudioMilestones':
            _optionalAudioMilestones.map((e) => e.name).toList(),
        'finishCelebration': _finishCelebration.name,
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
        'imuLongAxis': _imuLongAxis.name,
        'imuInvertLongitudinal': _imuInvertLongitudinal,
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

  Duration get _autoConnectPeriod =>
      _appInForeground ? _autoConnectFgPeriod : _autoConnectBgPeriod;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (inForeground == _appInForeground) return;
    _appInForeground = inForeground;
    // Faster retries while the dashboard is visible; slower in background.
    if (!_isConnected && !_autoConnectSuppressed) {
      _startAutoConnectLoop();
    }
  }

  void _startAutoConnectLoop() {
    if (_autoConnectSuppressed || _isConnected) return;
    _autoConnectTimer?.cancel();
    // Immediate attempt, then retry while OpenDragy is away / BT warming up.
    unawaited(_tickAutoConnect());
    _autoConnectTimer = Timer.periodic(_autoConnectPeriod, (_) {
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
      _cancelArmCalibration();
      _runRaw.clear();
      _metrics = _physicsEngine.reset();
      _lastGpsUpdateTime = null;
      notifyListeners();
    }
    await _releasePocketOrKeepAlive();
    await PocketForegroundService.bringAppToForeground();
  }

  Future<void> _handlePocketDisarm() async {
    _isArmed = false;
    _cancelArmCalibration();
    if (!_metrics.isRunning) {
      _runRaw.clear();
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
      _cancelArmCalibration();
      _runRaw.clear();
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
      _cancelArmCalibration();
      _runRaw.clear();
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
    _cancelArmCalibration();
    _runRaw.clear();
    _metrics = _physicsEngine.reset();
    _lastGpsUpdateTime = null;
    unawaited(_releasePocketOrKeepAlive());
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final data = await _settingsService.load();
    _applySettingsMap(data);
    _applyScreenPolicy();
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
    _pushCarStateThrottled(force: true);
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
    _pushCarStateThrottled(force: true);
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
    if (index != -1) {
      _vehicles[index] = vehicle;
      await _saveGarage();
      notifyListeners();
      _pushCarStateThrottled(force: true);
    }
  }

  Future<void> deleteVehicle(String id) async {
    _vehicles.removeWhere((v) => v.id == id);
    if (_activeVehicleId == id) {
      _activeVehicleId = _vehicles.isNotEmpty ? _vehicles.first.id : null;
    }
    await _saveGarage();
    notifyListeners();
    _pushCarStateThrottled(force: true);
  }

  Future<void> setActiveVehicle(String id) async {
    _activeVehicleId = id;
    await _saveGarage();
    notifyListeners();
    _pushCarStateThrottled(force: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onPocketTaskData);
    _stopAutoConnectLoop();
    _stopReconnectLoop();
    _adapterStateSubscription?.cancel();
    _uiTimer?.cancel();
    _nmeaSubscription?.cancel();
    _odgpSubscription?.cancel();
    _imuSubscription?.cancel();
    _connectionSubscription?.cancel();
    WakelockPlus.disable();
    if (_isRideRecording) {
      unawaited(_rideRecorder.stop(vehicleName: activeVehicle?.displayName));
    }
    unawaited(PocketForegroundService.stop());
    unawaited(_milestoneAudio.dispose());
    super.dispose();
  }
}


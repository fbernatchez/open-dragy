/// Raw GPS sample captured around an armed drag/interval run.
class RawGpsSample {
  final int elapsedMs;
  final String timeUtc;
  final double? latitude;
  final double? longitude;
  final double? altitudeM;
  final double? speedKmh;
  final double? hdop;
  final int? satellites;
  final int? fixQuality;

  const RawGpsSample({
    required this.elapsedMs,
    required this.timeUtc,
    this.latitude,
    this.longitude,
    this.altitudeM,
    this.speedKmh,
    this.hdop,
    this.satellites,
    this.fixQuality,
  });

  Map<String, dynamic> toJson() => {
        'elapsedMs': elapsedMs,
        'timeUtc': timeUtc,
        'lat': latitude,
        'lon': longitude,
        'altM': altitudeM,
        'speedKmh': speedKmh,
        'hdop': hdop,
        'sats': satellites,
        'fixQuality': fixQuality,
      };

  factory RawGpsSample.fromJson(Map<String, dynamic> json) {
    return RawGpsSample(
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      timeUtc: json['timeUtc'] as String? ?? '',
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      altitudeM: (json['altM'] as num?)?.toDouble(),
      speedKmh: (json['speedKmh'] as num?)?.toDouble(),
      hdop: (json['hdop'] as num?)?.toDouble(),
      satellites: (json['sats'] as num?)?.toInt(),
      fixQuality: (json['fixQuality'] as num?)?.toInt(),
    );
  }
}

/// Raw IMU sample (g units, uncalibrated axes from BMI160).
class RawImuSample {
  final int elapsedMs;
  final double axG;
  final double ayG;
  final double azG;

  const RawImuSample({
    required this.elapsedMs,
    required this.axG,
    required this.ayG,
    required this.azG,
  });

  Map<String, dynamic> toJson() => {
        'elapsedMs': elapsedMs,
        'axG': axG,
        'ayG': ayG,
        'azG': azG,
      };

  factory RawImuSample.fromJson(Map<String, dynamic> json) {
    return RawImuSample(
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      axG: (json['axG'] as num?)?.toDouble() ?? 0,
      ayG: (json['ayG'] as num?)?.toDouble() ?? 0,
      azG: (json['azG'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// In-memory capture while armed / during a timed run.
class RunRawCapture {
  /// Keep ~12 s of pre-roll while waiting for launch (~10 Hz GPS / ~100 Hz IMU).
  static const int maxPreGps = 120;
  static const int maxPreImu = 1250;

  /// Hard caps for a full run (+ pre-roll).
  static const int maxGps = 2500;
  static const int maxImu = 8000;

  DateTime? _startedAtUtc;
  bool _runActive = false;
  int? runStartElapsedMs;

  final List<RawGpsSample> gps = [];
  final List<RawImuSample> imu = [];

  bool get isActive => _startedAtUtc != null;
  bool get hasData => gps.isNotEmpty || imu.isNotEmpty;

  void startArmed() {
    clear();
    _startedAtUtc = DateTime.now().toUtc();
  }

  void markRunStarted() {
    if (!_runActive) {
      _runActive = true;
      runStartElapsedMs = _elapsedNow();
    }
  }

  void clear() {
    _startedAtUtc = null;
    _runActive = false;
    runStartElapsedMs = null;
    gps.clear();
    imu.clear();
  }

  int _elapsedNow() {
    final start = _startedAtUtc;
    if (start == null) return 0;
    return DateTime.now().toUtc().difference(start).inMilliseconds;
  }

  void addGps({
    double? latitude,
    double? longitude,
    double? altitudeM,
    double? speedKmh,
    double? hdop,
    int? satellites,
    int? fixQuality,
  }) {
    if (_startedAtUtc == null) return;
    final now = DateTime.now().toUtc();
    gps.add(
      RawGpsSample(
        elapsedMs: now.difference(_startedAtUtc!).inMilliseconds,
        timeUtc: now.toIso8601String(),
        latitude: latitude,
        longitude: longitude,
        altitudeM: altitudeM,
        speedKmh: speedKmh,
        hdop: hdop,
        satellites: satellites,
        fixQuality: fixQuality,
      ),
    );
    if (!_runActive && gps.length > maxPreGps) {
      gps.removeRange(0, gps.length - maxPreGps);
    } else if (gps.length > maxGps) {
      gps.removeAt(0);
    }
  }

  void addImu({
    required double axG,
    required double ayG,
    required double azG,
  }) {
    if (_startedAtUtc == null) return;
    imu.add(
      RawImuSample(
        elapsedMs: _elapsedNow(),
        axG: axG,
        ayG: ayG,
        azG: azG,
      ),
    );
    if (!_runActive && imu.length > maxPreImu) {
      imu.removeRange(0, imu.length - maxPreImu);
    } else if (imu.length > maxImu) {
      imu.removeAt(0);
    }
  }

  /// Snapshot for persistence (deep-enough for our immutable sample classes).
  Map<String, dynamic> toJsonBlock() => {
        'version': 1,
        'runStartElapsedMs': runStartElapsedMs,
        'gps': gps.map((e) => e.toJson()).toList(),
        'imu': imu.map((e) => e.toJson()).toList(),
      };

  static String gpsCsvHeader() =>
      'elapsed_ms,time_utc,lat,lon,speed_kmh,hdop,sats,fix_quality,alt_m';

  static String imuCsvHeader() => 'elapsed_ms,ax_g,ay_g,az_g';

  String toGpsCsv() {
    final buf = StringBuffer('${gpsCsvHeader()}\n');
    for (final s in gps) {
      buf.writeln(
        '${s.elapsedMs},${s.timeUtc},'
        '${s.latitude ?? ''},${s.longitude ?? ''},'
        '${s.speedKmh?.toStringAsFixed(3) ?? ''},'
        '${s.hdop?.toStringAsFixed(2) ?? ''},'
        '${s.satellites ?? ''},${s.fixQuality ?? ''},'
        '${s.altitudeM?.toStringAsFixed(2) ?? ''}',
      );
    }
    return buf.toString();
  }

  String toImuCsv() {
    final buf = StringBuffer('${imuCsvHeader()}\n');
    for (final s in imu) {
      buf.writeln(
        '${s.elapsedMs},'
        '${s.axG.toStringAsFixed(5)},'
        '${s.ayG.toStringAsFixed(5)},'
        '${s.azG.toStringAsFixed(5)}',
      );
    }
    return buf.toString();
  }
}

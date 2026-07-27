import 'gps_pvt_sample.dart';

/// Raw GPS sample captured around an armed drag/interval run.
class RawGpsSample {
  final int elapsedMs;
  final String timeUtc;
  final double? latitude;
  final double? longitude;
  final double? altitudeM;
  final double? speedKmh;
  final int? iTowMs;
  final double? hAccM;
  final double? vAccM;
  final double? sAccMps;
  final double? headingDeg;
  final int? fixType;
  final double? hdop;
  final int? satellites;
  final bool usedPvt;

  const RawGpsSample({
    required this.elapsedMs,
    required this.timeUtc,
    this.latitude,
    this.longitude,
    this.altitudeM,
    this.speedKmh,
    this.iTowMs,
    this.hAccM,
    this.vAccM,
    this.sAccMps,
    this.headingDeg,
    this.fixType,
    this.hdop,
    this.satellites,
    this.usedPvt = true,
  });

  /// Legacy alias kept for JSON from older app versions.
  int? get fixQuality => fixType;

  factory RawGpsSample.fromPvt({
    required int elapsedMs,
    required String timeUtc,
    required GpsPvtSample pvt,
  }) {
    return RawGpsSample(
      elapsedMs: elapsedMs,
      timeUtc: timeUtc,
      latitude: pvt.latitude,
      longitude: pvt.longitude,
      altitudeM: pvt.altitudeM,
      speedKmh: pvt.speedKmh,
      iTowMs: pvt.iTowMs,
      hAccM: pvt.hAccM,
      vAccM: pvt.vAccM,
      sAccMps: pvt.sAccMps,
      headingDeg: pvt.headingDeg,
      fixType: pvt.fixType,
      hdop: pvt.hdop,
      satellites: pvt.satellites,
      usedPvt: pvt.usedPvt,
    );
  }

  Map<String, dynamic> toJson() => {
        'elapsedMs': elapsedMs,
        'timeUtc': timeUtc,
        'lat': latitude,
        'lon': longitude,
        'altM': altitudeM,
        'speedKmh': speedKmh,
        'iTowMs': iTowMs,
        'hAccM': hAccM,
        'vAccM': vAccM,
        'sAccMps': sAccMps,
        'headingDeg': headingDeg,
        'fixType': fixType,
        'fixQuality': fixType,
        'hdop': hdop,
        'sats': satellites,
        'usedPvt': usedPvt,
      };

  factory RawGpsSample.fromJson(Map<String, dynamic> json) {
    return RawGpsSample(
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      timeUtc: json['timeUtc'] as String? ?? '',
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      altitudeM: (json['altM'] as num?)?.toDouble(),
      speedKmh: (json['speedKmh'] as num?)?.toDouble(),
      iTowMs: (json['iTowMs'] as num?)?.toInt(),
      hAccM: (json['hAccM'] as num?)?.toDouble(),
      vAccM: (json['vAccM'] as num?)?.toDouble(),
      sAccMps: (json['sAccMps'] as num?)?.toDouble(),
      headingDeg: (json['headingDeg'] as num?)?.toDouble(),
      fixType: (json['fixType'] as num?)?.toInt() ??
          (json['fixQuality'] as num?)?.toInt(),
      hdop: (json['hdop'] as num?)?.toDouble(),
      satellites: (json['sats'] as num?)?.toInt(),
      usedPvt: json['usedPvt'] as bool? ?? true,
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

  void addGpsPvt(GpsPvtSample sample) {
    if (_startedAtUtc == null) return;
    final now = DateTime.now().toUtc();
    gps.add(
      RawGpsSample.fromPvt(
        elapsedMs: now.difference(_startedAtUtc!).inMilliseconds,
        timeUtc: now.toIso8601String(),
        pvt: sample,
      ),
    );
    _trimGps();
  }

  void _trimGps() {
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
        'version': 2,
        'runStartElapsedMs': runStartElapsedMs,
        'gps': gps.map((e) => e.toJson()).toList(),
        'imu': imu.map((e) => e.toJson()).toList(),
      };

  static const String gpsCsvHeader =
      'elapsed_ms,time_utc,i_tow_ms,lat,lon,speed_kmh,'
      'h_acc_m,v_acc_m,s_acc_mps,heading_deg,fix_type,hdop,sats,alt_m,used_pvt';

  static String imuCsvHeader() => 'elapsed_ms,ax_g,ay_g,az_g';

  String toGpsCsv() {
    final buf = StringBuffer('$gpsCsvHeader\n');
    for (final s in gps) {
      buf.writeln(
        '${s.elapsedMs},${s.timeUtc},'
        '${s.iTowMs ?? ''},'
        '${s.latitude ?? ''},${s.longitude ?? ''},'
        '${s.speedKmh != null ? s.speedKmh!.toStringAsFixed(3) : ''},'
        '${s.hAccM != null ? s.hAccM!.toStringAsFixed(3) : ''},'
        '${s.vAccM != null ? s.vAccM!.toStringAsFixed(3) : ''},'
        '${s.sAccMps != null ? s.sAccMps!.toStringAsFixed(3) : ''},'
        '${s.headingDeg != null ? s.headingDeg!.toStringAsFixed(2) : ''},'
        '${s.fixType ?? ''},'
        '${s.hdop != null ? s.hdop!.toStringAsFixed(2) : ''},'
        '${s.satellites ?? ''},'
        '${s.altitudeM != null ? s.altitudeM!.toStringAsFixed(2) : ''},'
        '${s.usedPvt ? 1 : 0}',
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

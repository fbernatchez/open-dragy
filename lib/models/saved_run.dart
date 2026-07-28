import 'dart:math' as math;

import 'race_metrics.dart';
import 'raw_run_log.dart';
import 'run_trust.dart';

class SavedRun {
  static const int currentAlgorithmVersion = 2;

  final String id;
  final DateTime dateTime;
  final RaceMetrics metrics;
  final int algorithmVersion;
  final String? notes;
  final double? temperature; // in Celsius
  final double? humidity; // in %
  /// Wind speed at 10 m (m/s).
  final double? windSpeedMps;

  /// Meteorological wind-from direction (degrees).
  final double? windFromDeg;

  /// Surface pressure (hPa).
  final double? pressureHpa;

  /// Average GPS heading during the timed run (degrees).
  final double? runHeadingDeg;

  /// Positive = headwind along run heading (m/s).
  final double? headwindMps;
  final String? vehicleId;
  final String? vehicleName; // snapshot of display name at run time

  /// Raw GPS samples around the run (pre-roll + run). Optional for older saves.
  final List<RawGpsSample>? rawGps;

  /// Raw IMU samples (g). Optional for older saves.
  final List<RawImuSample>? rawImu;

  /// Elapsed ms (in raw capture timeline) when the timed run started.
  final int? rawRunStartElapsedMs;

  /// GPS trust badge (hAcc / sAcc / SV / PVT). Null on older saves.
  final RunTrust? trust;

  SavedRun({
    required this.id,
    required this.dateTime,
    required this.metrics,
    this.algorithmVersion = currentAlgorithmVersion,
    this.notes,
    this.temperature,
    this.humidity,
    this.windSpeedMps,
    this.windFromDeg,
    this.pressureHpa,
    this.runHeadingDeg,
    this.headwindMps,
    this.vehicleId,
    this.vehicleName,
    this.rawGps,
    this.rawImu,
    this.rawRunStartElapsedMs,
    this.trust,
  });

  bool get hasRawLog =>
      (rawGps != null && rawGps!.isNotEmpty) ||
      (rawImu != null && rawImu!.isNotEmpty);

  RunTrust get effectiveTrust =>
      trust ??
      RunTrust.fromRawGps(rawGps, runStartElapsedMs: rawRunStartElapsedMs) ??
      const RunTrust(level: RunTrustLevel.unknown);

  SavedRun copyWith({
    String? id,
    DateTime? dateTime,
    RaceMetrics? metrics,
    int? algorithmVersion,
    String? notes,
    double? temperature,
    double? humidity,
    double? windSpeedMps,
    double? windFromDeg,
    double? pressureHpa,
    double? runHeadingDeg,
    double? headwindMps,
    String? vehicleId,
    String? vehicleName,
    List<RawGpsSample>? rawGps,
    List<RawImuSample>? rawImu,
    int? rawRunStartElapsedMs,
    RunTrust? trust,
  }) {
    return SavedRun(
      id: id ?? this.id,
      dateTime: dateTime ?? this.dateTime,
      metrics: metrics ?? this.metrics,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      notes: notes ?? this.notes,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      windSpeedMps: windSpeedMps ?? this.windSpeedMps,
      windFromDeg: windFromDeg ?? this.windFromDeg,
      pressureHpa: pressureHpa ?? this.pressureHpa,
      runHeadingDeg: runHeadingDeg ?? this.runHeadingDeg,
      headwindMps: headwindMps ?? this.headwindMps,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      rawGps: rawGps ?? this.rawGps,
      rawImu: rawImu ?? this.rawImu,
      rawRunStartElapsedMs: rawRunStartElapsedMs ?? this.rawRunStartElapsedMs,
      trust: trust ?? this.trust,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateTime': dateTime.toIso8601String(),
      'metrics': metrics.toJson(),
      'algorithmVersion': algorithmVersion,
      'notes': notes,
      'temperature': temperature,
      'humidity': humidity,
      'windSpeedMps': windSpeedMps,
      'windFromDeg': windFromDeg,
      'pressureHpa': pressureHpa,
      'runHeadingDeg': runHeadingDeg,
      'headwindMps': headwindMps,
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      if (trust != null) 'trust': trust!.toJson(),
      if (rawGps != null || rawImu != null)
        'raw': {
          'version': 3,
          'runStartElapsedMs': rawRunStartElapsedMs,
          'gps': rawGps?.map((e) => e.toJson()).toList() ?? const [],
          'imu': rawImu?.map((e) => e.toJson()).toList() ?? const [],
        },
    };
  }

  factory SavedRun.fromJson(Map<String, dynamic> json) {
    List<RawGpsSample>? rawGps;
    List<RawImuSample>? rawImu;
    int? rawRunStartElapsedMs;

    final raw = json['raw'];
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      rawRunStartElapsedMs = (map['runStartElapsedMs'] as num?)?.toInt();
      final gpsList = map['gps'];
      if (gpsList is List) {
        rawGps = gpsList
            .whereType<Map>()
            .map((e) => RawGpsSample.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      final imuList = map['imu'];
      if (imuList is List) {
        rawImu = imuList
            .whereType<Map>()
            .map((e) => RawImuSample.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    RunTrust? trust;
    final trustJson = json['trust'];
    if (trustJson is Map) {
      trust = RunTrust.fromJson(Map<String, dynamic>.from(trustJson));
    }

    return SavedRun(
      id: json['id'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      metrics: RaceMetrics.fromJson(
        Map<String, dynamic>.from(json['metrics'] as Map),
      ),
      algorithmVersion: (json['algorithmVersion'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
      temperature: json['temperature'] != null
          ? (json['temperature'] as num).toDouble()
          : null,
      humidity: json['humidity'] != null
          ? (json['humidity'] as num).toDouble()
          : null,
      windSpeedMps: (json['windSpeedMps'] as num?)?.toDouble(),
      windFromDeg: (json['windFromDeg'] as num?)?.toDouble(),
      pressureHpa: (json['pressureHpa'] as num?)?.toDouble(),
      runHeadingDeg: (json['runHeadingDeg'] as num?)?.toDouble(),
      headwindMps: (json['headwindMps'] as num?)?.toDouble(),
      vehicleId: json['vehicleId'] as String?,
      vehicleName: json['vehicleName'] as String?,
      rawGps: rawGps,
      rawImu: rawImu,
      rawRunStartElapsedMs: rawRunStartElapsedMs,
      trust: trust,
    );
  }

  /// Mean GPS heading from samples after timed start (when available).
  static double? averageRunHeading({
    required List<RawGpsSample>? rawGps,
    int? runStartElapsedMs,
  }) {
    if (rawGps == null || rawGps.isEmpty) return null;
    final start = runStartElapsedMs ?? 0;
    double sumSin = 0;
    double sumCos = 0;
    var n = 0;
    for (final s in rawGps) {
      if (s.elapsedMs < start) continue;
      final h = s.headingDeg;
      if (h == null) continue;
      final rad = h * math.pi / 180.0;
      sumSin += math.sin(rad);
      sumCos += math.cos(rad);
      n++;
    }
    if (n < 3) return null;
    var deg = math.atan2(sumSin / n, sumCos / n) * 180.0 / math.pi;
    if (deg < 0) deg += 360.0;
    return deg;
  }
}

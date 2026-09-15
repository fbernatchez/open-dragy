import 'dart:math' as math;

import 'package:open_dragy/models/race_test.dart';

class DataPoint {
  final double elapsedTime;
  final double speedKmh;
  final double gForce;
  final double? altitude; // Elevation in meters

  const DataPoint({
    required this.elapsedTime,
    required this.speedKmh,
    required this.gForce,
    this.altitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'elapsedTime': elapsedTime,
      'speedKmh': speedKmh,
      'gForce': gForce,
      'altitude': altitude,
    };
  }

  factory DataPoint.fromJson(Map<String, dynamic> json) {
    return DataPoint(
      elapsedTime: (json['elapsedTime'] as num).toDouble(),
      speedKmh: (json['speedKmh'] as num).toDouble(),
      gForce: (json['gForce'] as num).toDouble(),
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
    );
  }
}

class RaceMetrics {
  final double speedKmh;
  final double distanceMeters;
  final double gForce;
  final double elapsedTime;

  // Timers
  final Map<String, double> testTimes;

  // Global rollout timer (needed for NHRA calculations)
  final double? rolloutTime1ft;

  // Elevation
  final double? startAltitude; // Start elevation in meters

  // Mode & Target Info
  final RunMode? runMode;
  final double? testDistance;
  final DistanceUnit? testDistanceUnit;
  final double? testStartSpeed;
  final double? testEndSpeed;
  final SpeedUnit? testSpeedUnit;

  final bool isRunning;
  final List<DataPoint> history;

  bool get isValidRun {
    if (history.isEmpty) return false;
    final maxSpeed = history.map((e) => e.speedKmh).reduce(math.max);
    return elapsedTime >= 1.0 && maxSpeed >= 10.0;
  }

  RaceMetrics({
    this.speedKmh = 0.0,
    this.distanceMeters = 0.0,
    this.gForce = 0.0,
    this.elapsedTime = 0.0,
    Map<String, double>? testTimes,
    this.rolloutTime1ft,
    this.startAltitude,
    this.runMode,
    this.testDistance,
    this.testDistanceUnit,
    this.testStartSpeed,
    this.testEndSpeed,
    this.testSpeedUnit,
    this.isRunning = false,
    this.history = const [],
  }) : testTimes = testTimes ?? const {};

  RaceMetrics copyWith({
    double? speedKmh,
    double? distanceMeters,
    double? gForce,
    double? elapsedTime,
    Map<String, double>? testTimes,
    double? rolloutTime1ft,
    double? startAltitude,
    RunMode? runMode,
    double? testDistance,
    DistanceUnit? testDistanceUnit,
    double? testStartSpeed,
    double? testEndSpeed,
    SpeedUnit? testSpeedUnit,
    bool? isRunning,
    List<DataPoint>? history,
  }) {
    return RaceMetrics(
      speedKmh: speedKmh ?? this.speedKmh,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      gForce: gForce ?? this.gForce,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      testTimes: testTimes ?? this.testTimes,
      rolloutTime1ft: rolloutTime1ft ?? this.rolloutTime1ft,
      startAltitude: startAltitude ?? this.startAltitude,
      runMode: runMode ?? this.runMode,
      testDistance: testDistance ?? this.testDistance,
      testDistanceUnit: testDistanceUnit ?? this.testDistanceUnit,
      testStartSpeed: testStartSpeed ?? this.testStartSpeed,
      testEndSpeed: testEndSpeed ?? this.testEndSpeed,
      testSpeedUnit: testSpeedUnit ?? this.testSpeedUnit,
      isRunning: isRunning ?? this.isRunning,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speedKmh': speedKmh,
      'distanceMeters': distanceMeters,
      'gForce': gForce,
      'elapsedTime': elapsedTime,
      'testTimes': testTimes,
      'rolloutTime1ft': rolloutTime1ft,
      'startAltitude': startAltitude,
      'runMode': runMode?.name,
      'testDistance': testDistance,
      'testDistanceUnit': testDistanceUnit?.name,
      'testStartSpeed': testStartSpeed,
      'testEndSpeed': testEndSpeed,
      'testSpeedUnit': testSpeedUnit?.name,
      'history': history.map((e) => e.toJson()).toList(),
    };
  }

  factory RaceMetrics.fromJson(Map<String, dynamic> json) {
    return RaceMetrics(
      speedKmh: (json['speedKmh'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      gForce: (json['gForce'] as num).toDouble(),
      elapsedTime: (json['elapsedTime'] as num).toDouble(),
      testTimes: (json['testTimes'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ) ??
          {},
      rolloutTime1ft: json['rolloutTime1ft'] != null
          ? (json['rolloutTime1ft'] as num).toDouble()
          : null,
      startAltitude: json['startAltitude'] != null
          ? (json['startAltitude'] as num).toDouble()
          : null,
      runMode: json['runMode'] != null
          ? RunMode.values.asNameMap()[json['runMode']]
          : null,
      testDistance: json['testDistance'] != null
          ? (json['testDistance'] as num).toDouble()
          : null,
      testDistanceUnit: json['testDistanceUnit'] != null
          ? DistanceUnit.values.asNameMap()[json['testDistanceUnit']]
          : null,
      testStartSpeed: json['testStartSpeed'] != null
          ? (json['testStartSpeed'] as num).toDouble()
          : null,
      testEndSpeed: json['testEndSpeed'] != null
          ? (json['testEndSpeed'] as num).toDouble()
          : null,
      testSpeedUnit: json['testSpeedUnit'] != null
          ? SpeedUnit.values.asNameMap()[json['testSpeedUnit']]
          : null,
      isRunning: false,
      history: (json['history'] as List? ?? [])
          .map((e) => DataPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

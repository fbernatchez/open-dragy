import 'dart:math' as math;

import 'package:open_dragy/models/race_target.dart';

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

  // Timers and Speeds
  final Map<String, double> targetTimes;
  final Map<String, double> targetSpeeds;

  // Global rollout timer (needed for NHRA calculations)
  final double? rolloutTime1ft;

  // Elevation
  final double? startAltitude; // Start elevation in meters

  // Mode & Target Info
  final RunMode? runMode;
  final double? targetDistance;
  final DistanceUnit? targetDistanceUnit;
  final double? targetStartSpeed;
  final double? targetEndSpeed;
  final SpeedUnit? targetSpeedUnit;

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
    Map<String, double>? targetTimes,
    Map<String, double>? targetSpeeds,
    this.rolloutTime1ft,
    this.startAltitude,
    this.runMode,
    this.targetDistance,
    this.targetDistanceUnit,
    this.targetStartSpeed,
    this.targetEndSpeed,
    this.targetSpeedUnit,
    this.isRunning = false,
    this.history = const [],
  })  : targetTimes = targetTimes ?? const {},
        targetSpeeds = targetSpeeds ?? const {};

  RaceMetrics copyWith({
    double? speedKmh,
    double? distanceMeters,
    double? gForce,
    double? elapsedTime,
    Map<String, double>? targetTimes,
    Map<String, double>? targetSpeeds,
    double? rolloutTime1ft,
    double? startAltitude,
    RunMode? runMode,
    double? targetDistance,
    DistanceUnit? targetDistanceUnit,
    double? targetStartSpeed,
    double? targetEndSpeed,
    SpeedUnit? targetSpeedUnit,
    bool? isRunning,
    List<DataPoint>? history,
  }) {
    return RaceMetrics(
      speedKmh: speedKmh ?? this.speedKmh,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      gForce: gForce ?? this.gForce,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      targetTimes: targetTimes ?? this.targetTimes,
      targetSpeeds: targetSpeeds ?? this.targetSpeeds,
      rolloutTime1ft: rolloutTime1ft ?? this.rolloutTime1ft,
      startAltitude: startAltitude ?? this.startAltitude,
      runMode: runMode ?? this.runMode,
      targetDistance: targetDistance ?? this.targetDistance,
      targetDistanceUnit: targetDistanceUnit ?? this.targetDistanceUnit,
      targetStartSpeed: targetStartSpeed ?? this.targetStartSpeed,
      targetEndSpeed: targetEndSpeed ?? this.targetEndSpeed,
      targetSpeedUnit: targetSpeedUnit ?? this.targetSpeedUnit,
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
      'targetTimes': targetTimes,
      'targetSpeeds': targetSpeeds,
      'rolloutTime1ft': rolloutTime1ft,
      'startAltitude': startAltitude,
      'runMode': runMode?.name,
      'targetDistance': targetDistance,
      'targetDistanceUnit': targetDistanceUnit?.name,
      'targetStartSpeed': targetStartSpeed,
      'targetEndSpeed': targetEndSpeed,
      'targetSpeedUnit': targetSpeedUnit?.name,
      'history': history.map((e) => e.toJson()).toList(),
    };
  }

  factory RaceMetrics.fromJson(Map<String, dynamic> json) {
    // Migration for legacy hardcoded target properties
    Map<String, double> migratedTargetTimes = {};
    if (json.containsKey('targetTimes')) {
      migratedTargetTimes = Map<String, double>.from(json['targetTimes']);
    } else {
      final legacyTimeKeys = {
        '60ft': 'time60ft',
        '330ft': 'time330ft',
        '0-60mph': 'time0to60mph',
        '0-100kmh': 'time0to100kmh',
        '1/8mile': 'time18Mile',
        '1000ft': 'time1000ft',
        '1/4mile': 'time14Mile',
        '1/2mile': 'time12Mile',
        '0-130mph': 'time0to130mph',
        '0-200kmh': 'time0to200kmh',
        '60-130mph': 'time60to130mph',
        '100-200kmh': 'time100to200kmh',
        '60ft_rollout': 'time60ftRollout',
        '330ft_rollout': 'time330ftRollout',
        '0-60mph_rollout': 'time0to60mphRollout',
        '0-100kmh_rollout': 'time0to100kmhRollout',
        '1/8mile_rollout': 'time18MileRollout',
        '1000ft_rollout': 'time1000ftRollout',
        '1/4mile_rollout': 'time14MileRollout',
        '1/2mile_rollout': 'time12MileRollout',
      };
      for (final entry in legacyTimeKeys.entries) {
        if (json[entry.value] != null) {
          migratedTargetTimes[entry.key] = (json[entry.value] as num).toDouble();
        }
      }
    }

    Map<String, double> migratedTargetSpeeds = {};
    if (json.containsKey('targetSpeeds')) {
      migratedTargetSpeeds = Map<String, double>.from(json['targetSpeeds']);
    } else {
      final legacySpeedKeys = {
        '1/8mile': 'trap18Mile',
        '1000ft': 'trap1000ft',
        '1/4mile': 'trap14Mile',
        '1/2mile': 'trap12Mile',
      };
      for (final entry in legacySpeedKeys.entries) {
        if (json[entry.value] != null) {
          migratedTargetSpeeds[entry.key] = (json[entry.value] as num).toDouble();
        }
      }
    }

    return RaceMetrics(
      speedKmh: (json['speedKmh'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      gForce: (json['gForce'] as num).toDouble(),
      elapsedTime: (json['elapsedTime'] as num).toDouble(),
      targetTimes: migratedTargetTimes,
      targetSpeeds: migratedTargetSpeeds,
      rolloutTime1ft: json['rolloutTime1ft'] != null
          ? (json['rolloutTime1ft'] as num).toDouble()
          : null,
      startAltitude: json['startAltitude'] != null
          ? (json['startAltitude'] as num).toDouble()
          : null,
      runMode: json['runMode'] != null
          ? RunMode.values.asNameMap()[json['runMode']]
          : null,
      targetDistance: json['targetDistance'] != null
          ? (json['targetDistance'] as num).toDouble()
          : null,
      targetDistanceUnit: json['targetDistanceUnit'] != null
          ? DistanceUnit.values.asNameMap()[json['targetDistanceUnit']]
          : null,
      targetStartSpeed: json['targetStartSpeed'] != null
          ? (json['targetStartSpeed'] as num).toDouble()
          : null,
      targetEndSpeed: json['targetEndSpeed'] != null
          ? (json['targetEndSpeed'] as num).toDouble()
          : null,
      targetSpeedUnit: json['targetSpeedUnit'] != null
          ? SpeedUnit.values.asNameMap()[json['targetSpeedUnit']]
          : null,
      isRunning: false,
      history: (json['history'] as List? ?? [])
          .map((e) => DataPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

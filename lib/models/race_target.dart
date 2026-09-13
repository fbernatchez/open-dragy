import 'race_metrics.dart';
import '../utils/unit_converter.dart';

enum DistanceUnit {
  feet,
  mile,
  meter,
  kilometer;

  String toJson() => name;
  static DistanceUnit fromJson(String name) => DistanceUnit.values.byName(name);
}

enum SpeedUnit {
  mph,
  kmh;

  String toJson() => name;
  static SpeedUnit fromJson(String name) => SpeedUnit.values.byName(name);
}

enum RunMode {
  drag,
  interval;

  String toJson() => name;
  static RunMode fromJson(String name) => RunMode.values.byName(name);
}

enum RaceDragTarget {
  sixtyFeet('60ft', 60.0, DistanceUnit.feet),
  threeHundredThirtyFeet('330ft', 330.0, DistanceUnit.feet),
  eighthMile('1/8 mile', 0.125, DistanceUnit.mile),
  thousandFeet('1000ft', 1000.0, DistanceUnit.feet),
  quarterMile('1/4 mile', 0.25, DistanceUnit.mile),
  halfMile('1/2 mile', 0.5, DistanceUnit.mile);

  final String label;
  final double distance;
  final DistanceUnit distanceUnit;
  const RaceDragTarget(this.label, this.distance, this.distanceUnit);
}

enum RaceIntervalTarget {
  zeroToSixtyMph('0-60 mph', '0-60mph', SpeedUnit.mph, 0.0, 96.5606),
  zeroToOneHundredMph(
    '0-100 mph',
    'custom_0_100_mph',
    SpeedUnit.mph,
    0.0,
    160.9344,
  ),
  fiftyToSeventyFiveMph(
    '50-75 mph',
    'custom_50_75_mph',
    SpeedUnit.mph,
    80.4672,
    120.7008,
  ),
  sixtyToOneHundredMph(
    '60-100 mph',
    'custom_60_100_mph',
    SpeedUnit.mph,
    96.5606,
    160.9344,
  ),
  sixtyToOneThirtyMph(
    '60-130 mph',
    '60-130mph',
    SpeedUnit.mph,
    96.5606,
    209.2147,
  ),
  zeroToOneThirtyMph('0-130 mph', '0-130mph', SpeedUnit.mph, 0.0, 209.2147),
  zeroToOneHundredKmh('0-100 km/h', '0-100kmh', SpeedUnit.kmh, 0.0, 100.0),
  zeroToOneSixtyKmh(
    '0-160 km/h',
    'custom_0_160_kmh',
    SpeedUnit.kmh,
    0.0,
    160.0,
  ),
  eightyToOneTwentyKmh(
    '80-120 km/h',
    'custom_80_120_kmh',
    SpeedUnit.kmh,
    80.0,
    120.0,
  ),
  oneHundredToOneSixtyKmh(
    '100-160 km/h',
    'custom_100_160_kmh',
    SpeedUnit.kmh,
    100.0,
    160.0,
  ),
  oneHundredToTwoHundredKmh(
    '100-200 km/h',
    '100-200kmh',
    SpeedUnit.kmh,
    100.0,
    200.0,
  ),
  zeroToTwoHundredKmh('0-200 km/h', '0-200kmh', SpeedUnit.kmh, 0.0, 200.0),
  custom('Custom Range...', 'custom', null, null, null);

  final String label;
  final String id;
  final SpeedUnit? speedUnit;

  final double? startSpeedKmh;
  final double? endSpeedKmh;
  const RaceIntervalTarget(
    this.label,
    this.id,
    this.speedUnit,
    this.startSpeedKmh,
    this.endSpeedKmh,
  );
}

class RaceTarget {
  final String id;
  final String displayName;
  final String? ttsPhrase;
  final bool enableTts;

  final double? distance; // in meters or feet
  final DistanceUnit? distanceUnit;

  final double? startSpeed; // in km/h
  final double? endSpeed; // in km/h
  final SpeedUnit? speedUnit;
  final bool isOfficial;


  const RaceTarget({
    required this.id,
    required this.displayName,
    this.ttsPhrase,
    this.enableTts = true,
    this.distance,
    this.distanceUnit,
    this.startSpeed,
    this.endSpeed,
    this.speedUnit,
    this.isOfficial = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'ttsPhrase': ttsPhrase,
      'enableTts': enableTts,
      'distance': distance,
      'distanceUnit': distanceUnit?.name,
      'startSpeed': startSpeed,
      'endSpeed': endSpeed,
      'speedUnit': speedUnit?.name,
      'isOfficial': isOfficial,
    };
  }

  factory RaceTarget.fromJson(Map<String, dynamic> json) {
    return RaceTarget(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      ttsPhrase: json['ttsPhrase'] as String?,
      enableTts: json['enableTts'] as bool? ?? true,
      distance: (json['distance'] as num?)?.toDouble(),
      distanceUnit: json['distanceUnit'] != null ? DistanceUnit.fromJson(json['distanceUnit'] as String) : null,
      startSpeed: (json['startSpeed'] as num?)?.toDouble(),
      endSpeed: (json['endSpeed'] as num?)?.toDouble(),
      speedUnit: json['speedUnit'] != null ? SpeedUnit.fromJson(json['speedUnit'] as String) : null,
      isOfficial: json['isOfficial'] as bool? ?? false,
    );
  }
}

class HistoryCategory {
  final String id;
  final String displayName;
  final bool isOfficial;

  // Custom interval details if applicable
  final double? startSpeed;
  final double? endSpeed;
  final SpeedUnit? speedUnit;

  const HistoryCategory({
    required this.id,
    required this.displayName,
    required this.isOfficial,
    this.startSpeed,
    this.endSpeed,
    this.speedUnit,
  });
}

const List<RaceTarget> officialTests = [
  RaceTarget(
    id: '60ft',
    displayName: '60ft',
    distance: 60.0,
    distanceUnit: DistanceUnit.feet,
  ),
  RaceTarget(
    id: '330ft',
    displayName: '330ft',
    distance: 330.0,
    distanceUnit: DistanceUnit.feet,
  ),
  RaceTarget(
    id: '0-60mph',
    displayName: '0-60 mph',
    ttsPhrase: 'Sixty',
    startSpeed: 0.0,
    endSpeed: 96.56064, // 60 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  RaceTarget(
    id: '0-100kmh',
    displayName: '0-100 km/h',
    ttsPhrase: 'One hundred',
    startSpeed: 0.0,
    endSpeed: 100.0,
    speedUnit: SpeedUnit.kmh,
  ),
  RaceTarget(
    id: '1/8mile',
    displayName: '1/8 mile',
    ttsPhrase: 'Eighth mile',
    distance: 0.125,
    distanceUnit: DistanceUnit.mile,
  ),
  RaceTarget(
    id: '1000ft',
    displayName: '1000ft',
    distance: 1000.0,
    distanceUnit: DistanceUnit.feet,
  ),
  RaceTarget(
    id: '1/4mile',
    displayName: '1/4 mile',
    ttsPhrase: 'Quarter mile',
    distance: 0.25,
    distanceUnit: DistanceUnit.mile,
  ),
  RaceTarget(
    id: '1/2mile',
    displayName: '1/2 mile',
    ttsPhrase: 'Half mile',
    distance: 0.5,
    distanceUnit: DistanceUnit.mile,
  ),
  RaceTarget(
    id: '0-130mph',
    displayName: '0-130 mph',
    ttsPhrase: 'One thirty',
    startSpeed: 0.0,
    endSpeed: 209.21472, // 130 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  RaceTarget(
    id: '0-200kmh',
    displayName: '0-200 km/h',
    ttsPhrase: 'Two hundred',
    startSpeed: 0.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
  // Interval tests
  RaceTarget(
    id: '60-130mph',
    displayName: '60-130 mph',
    startSpeed: 96.56064,
    endSpeed: 209.21472,
    speedUnit: SpeedUnit.mph,
  ),
  RaceTarget(
    id: '100-200kmh',
    displayName: '100-200 km/h',
    startSpeed: 100.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
  RaceTarget(
    id: '0-300kmh',
    displayName: '0-300 km/h',
    ttsPhrase: 'Three hundred',
    startSpeed: 0.0,
    endSpeed: 300.0,
    speedUnit: SpeedUnit.kmh,
  ),
  RaceTarget(
    id: '200-300kmh',
    displayName: '200-300 km/h',
    startSpeed: 200.0,
    endSpeed: 300.0,
    speedUnit: SpeedUnit.kmh,
  ),
  RaceTarget(
    id: '0-200mph',
    displayName: '0-200 mph',
    ttsPhrase: 'Two hundred',
    startSpeed: 0.0,
    endSpeed: 321.8688,
    speedUnit: SpeedUnit.mph,
  ),
  RaceTarget(
    id: '130-200mph',
    displayName: '130-200 mph',
    startSpeed: 209.21472,
    endSpeed: 321.8688,
    speedUnit: SpeedUnit.mph,
  ),
];

// Helper to retrieve precalculated fields from RaceMetrics
double? _getPrecalculatedTime(
  RaceMetrics m,
  String id, {
  bool useNhraRules = false,
}) {
  if (useNhraRules) {
    // 1. Check if we have an explicit legacy rollout key (e.g. '0-60mph_rollout')
    final legacyRolloutTime = m.targetTimes['${id}_rollout'];
    if (legacyRolloutTime != null) return legacyRolloutTime;

    // 2. Otherwise, check if we have the base time, and subtract rollout
    final baseTime = m.targetTimes[id];
    if (baseTime != null) {
      // Only apply rollout if it's a standing start target
      final isStandingStart = officialTests.any(
        (t) =>
            t.id == id &&
            (t.distance != null ||
                (t.startSpeed != null && t.startSpeed == 0.0)),
      );
      if (isStandingStart && m.rolloutTime1ft != null) {
        return baseTime - m.rolloutTime1ft!;
      }
      return baseTime; // Not a standing start, so no rollout
    }
    return null;
  } else {
    return m.targetTimes[id];
  }
}

// Convert distance units to meters
double convertToMeters(double distance, DistanceUnit unit) {
  switch (unit) {
    case DistanceUnit.feet:
      return distance * 0.3048;
    case DistanceUnit.mile:
      return distance * 1609.344;
    case DistanceUnit.meter:
      return distance;
    case DistanceUnit.kilometer:
      return distance * 1000.0;
  }
}

// Search and interpolate distance crossing time
double? _findDistanceCrossingTime(
  List<DataPoint> history,
  double targetMeters,
) {
  double currentDistance = 0.0;
  for (int i = 1; i < history.length; i++) {
    final prev = history[i - 1];
    final curr = history[i];
    final dt = curr.elapsedTime - prev.elapsedTime;
    final avgSpeedMs = ((prev.speedKmh / 3.6) + (curr.speedKmh / 3.6)) / 2;
    final stepDist = avgSpeedMs * dt;

    if (currentDistance + stepDist >= targetMeters) {
      final neededDist = targetMeters - currentDistance;
      double fraction = 0.0;
      if (stepDist > 0) {
        fraction = neededDist / stepDist;
      }
      return prev.elapsedTime + (dt * fraction);
    }
    currentDistance += stepDist;
  }
  return null;
}

// Search and interpolate speed crossing time
double? _findSpeedCrossingTime(
  List<DataPoint> history,
  double targetSpeedKmh,
  double startTimeOffset,
) {
  for (int i = 1; i < history.length; i++) {
    final prev = history[i - 1];
    final curr = history[i];
    if (prev.elapsedTime < startTimeOffset) continue;

    if (prev.speedKmh <= targetSpeedKmh && curr.speedKmh >= targetSpeedKmh) {
      if (prev.speedKmh == targetSpeedKmh) {
        return prev.elapsedTime;
      }
      final speedDiff = curr.speedKmh - prev.speedKmh;
      double fraction = 0.0;
      if (speedDiff > 0) {
        fraction = (targetSpeedKmh - prev.speedKmh) / speedDiff;
      }
      final dt = curr.elapsedTime - prev.elapsedTime;
      return prev.elapsedTime + (dt * fraction);
    }
  }
  return null;
}

// Calculate run times dynamically from history points
double? _calculateTimeFromHistory(
  RaceMetrics metrics,
  RaceTarget test, {
  bool useNhraRules = false,
}) {
  if (metrics.history.isEmpty) return null;

  if (test.distance != null && test.distanceUnit != null) {
    final targetMeters = convertToMeters(test.distance!, test.distanceUnit!);
    return _findDistanceCrossingTime(metrics.history, targetMeters);
  } else if (test.endSpeed != null) {
    final start = test.startSpeed ?? 0.0;
    if (start == 0.0) {
      final time = _findSpeedCrossingTime(metrics.history, test.endSpeed!, 0.0);
      if (time != null && useNhraRules && metrics.rolloutTime1ft != null) {
        return time - metrics.rolloutTime1ft!;
      }
      return time;
    } else {
      final startTime = _findSpeedCrossingTime(metrics.history, start, 0.0);
      if (startTime == null) return null;
      final endTime = _findSpeedCrossingTime(
        metrics.history,
        test.endSpeed!,
        startTime,
      );
      if (endTime == null) return null;
      return endTime - startTime;
    }
  }
  return null;
}

List<RaceTarget> getCompletedTests(
  RaceMetrics metrics, {
  bool useNhraRules = false,
  List<RaceTarget> activeTargets = officialTests,
}) {
  final List<RaceTarget> completed = [];

  for (final test in activeTargets) {
    final time = getCompletedTimeForCategory(
      metrics,
      test.id,
      useNhraRules: useNhraRules,
      activeTargets: activeTargets,
    );
    if (time != null) {
      completed.add(test);
    }
  }

  return completed;
}

double? getCompletedTimeForCategory(
  RaceMetrics metrics,
  String categoryId, {
  bool useNhraRules = false,
  List<RaceTarget> activeTargets = officialTests,
}) {
  final useRollout = useNhraRules && metrics.rolloutTime1ft != null;

  // 1. Check if it matches a target definition
  for (final test in activeTargets) {
    if (test.id == categoryId) {
      // Standing start tests require either drag mode or an interval run that started from 0.
      if (test.distance != null ||
          (test.startSpeed != null && test.startSpeed == 0.0)) {
        if (metrics.runMode != RunMode.drag &&
            metrics.targetStartSpeed != 0.0) {
          return null;
        }
      }

      // Fast path: Check standard precalculated fields
      final precalculated = _getPrecalculatedTime(
        metrics,
        test.id,
        useNhraRules: useRollout,
      );
      if (precalculated != null) return precalculated;

      // Fallback: Calculate dynamically from history coordinates
      return _calculateTimeFromHistory(metrics, test, useNhraRules: useRollout);
    }
  }

  return null;
}

double? getTrapSpeedForCategory(
  RaceMetrics metrics,
  String categoryId, {
  bool useNhraRules = false,
  List<RaceTarget> activeTargets = officialTests,
}) {
  final target = activeTargets.where((t) => t.id == categoryId).firstOrNull;
  if (target == null || target.distance == null || target.distanceUnit == null) {
    return metrics.targetSpeeds[categoryId];
  }

  final targetMeters = convertToMeters(target.distance!, target.distanceUnit!);
  
  final shouldApply66ftRule =
      useNhraRules &&
      metrics.runMode == RunMode.drag &&
      metrics.targetDistance != null &&
      (target.distance! - metrics.targetDistance!).abs() < 0.001 &&
      target.distanceUnit == metrics.targetDistanceUnit;

  if (shouldApply66ftRule && targetMeters > 0) {
    // Offset finish line by 1ft if rollout is applied (track starts timer after rollout)
    final finishLineMeters =
        targetMeters + (metrics.rolloutTime1ft != null ? 0.3048 : 0.0);
    final trapStartMeters =
        finishLineMeters - 20.1168; // 66 feet before finish

    if (trapStartMeters > 0) {
      final timeFinish = _findDistanceCrossingTime(
        metrics.history,
        finishLineMeters,
      );
      final timeStart = _findDistanceCrossingTime(
        metrics.history,
        trapStartMeters,
      );

      if (timeFinish != null && timeStart != null && timeFinish > timeStart) {
        final elapsedSeconds = timeFinish - timeStart;
        return (20.1168 / elapsedSeconds) * 3.6; // Speed in km/h
      }
    }
  }

  // Fallback to instantaneous trap speed
  return metrics.targetSpeeds[categoryId];
}

String getDisplayLabelForTarget({
  double? distance,
  dynamic distanceUnit,
  double? startSpeed,
  double? endSpeed,
  dynamic speedUnit,
  dynamic runMode,
}) {
  final isDrag = runMode is RunMode
      ? runMode == RunMode.drag
      : runMode == 'drag';
  if (isDrag) {
    if (distance != null && distanceUnit != null) {
      final unit = distanceUnit is DistanceUnit
          ? distanceUnit.name
          : distanceUnit.toString().toLowerCase();
      if (unit == 'feet') {
        return '${distance.round()}ft';
      } else if (unit == 'mile') {
        if (distance == 0.125) return '1/8 mile';
        if (distance == 0.25) return '1/4 mile';
        if (distance == 0.5) return '1/2 mile';
        return '$distance mile';
      } else if (unit == 'meter') {
        return '${distance.round()}m';
      }
    }
    return 'Drag';
  } else {
    if (startSpeed != null && endSpeed != null) {
      final unit = speedUnit is SpeedUnit
          ? speedUnit.name
          : speedUnit?.toString();
      if (unit == 'mph') {
        final start = UnitConverter.kmhToMph(startSpeed).round();
        final end = UnitConverter.kmhToMph(endSpeed).round();
        return '$start-$end mph';
      } else {
        final start = startSpeed.round();
        final end = endSpeed.round();
        return '$start-$end km/h';
      }
    }
    return 'Interval';
  }
}

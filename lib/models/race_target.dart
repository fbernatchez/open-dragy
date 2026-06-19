import 'race_metrics.dart';

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

class OfficialTest {
  final String id;
  final String displayName;

  // Criteria
  final double? distance;
  final DistanceUnit? distanceUnit;
  final double? startSpeed; // in km/h
  final double? endSpeed; // in km/h
  final SpeedUnit? speedUnit;

  const OfficialTest({
    required this.id,
    required this.displayName,
    this.distance,
    this.distanceUnit,
    this.startSpeed,
    this.endSpeed,
    this.speedUnit,
  });
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

const List<OfficialTest> officialTests = [
  OfficialTest(
    id: '60ft',
    displayName: '60ft',
    distance: 60.0,
    distanceUnit: DistanceUnit.feet,
  ),
  OfficialTest(
    id: '0-60mph',
    displayName: '0-60 mph',
    startSpeed: 0.0,
    endSpeed: 96.56064, // 60 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '0-100kmh',
    displayName: '0-100 km/h',
    startSpeed: 0.0,
    endSpeed: 100.0,
    speedUnit: SpeedUnit.kmh,
  ),
  OfficialTest(
    id: '1/8mile',
    displayName: '1/8 mile',
    distance: 0.125,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '1000ft',
    displayName: '1000ft',
    distance: 1000.0,
    distanceUnit: DistanceUnit.feet,
  ),
  OfficialTest(
    id: '1/4mile',
    displayName: '1/4 mile',
    distance: 0.25,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '1/2mile',
    displayName: '1/2 mile',
    distance: 0.5,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '0-130mph',
    displayName: '0-130 mph',
    startSpeed: 0.0,
    endSpeed: 209.21472, // 130 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '0-200kmh',
    displayName: '0-200 km/h',
    startSpeed: 0.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
  // Interval tests
  OfficialTest(
    id: '60-130mph',
    displayName: '60-130 mph',
    startSpeed: 96.56064,
    endSpeed: 209.21472,
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '100-200kmh',
    displayName: '100-200 km/h',
    startSpeed: 100.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
];

// Helper to retrieve precalculated fields from RaceMetrics
double? _getPrecalculatedTime(RaceMetrics m, String id, {bool showRollout = false}) {
  if (showRollout) {
    switch (id) {
      case '60ft':
        return m.time60ftRollout;
      case '0-60mph':
        return m.time0to60mphRollout;
      case '0-100kmh':
        return m.time0to100kmhRollout;
      case '1/8mile':
        return m.time18MileRollout;
      case '1000ft':
        return m.time1000ftRollout;
      case '1/4mile':
        return m.time14MileRollout;
      case '1/2mile':
        return m.time12MileRollout;
      case '0-130mph':
        return (m.time0to130mph != null && m.rolloutTime1ft != null)
            ? m.time0to130mph! - m.rolloutTime1ft!
            : null;
      case '0-200kmh':
        return (m.time0to200kmh != null && m.rolloutTime1ft != null)
            ? m.time0to200kmh! - m.rolloutTime1ft!
            : null;
      case '60-130mph':
        return m.time60to130mph;
      case '100-200kmh':
        return m.time100to200kmh;
      default:
        return null;
    }
  } else {
    switch (id) {
      case '60ft':
        return m.time60ft;
      case '0-60mph':
        return m.time0to60mph;
      case '0-100kmh':
        return m.time0to100kmh;
      case '1/8mile':
        return m.time18Mile;
      case '1000ft':
        return m.time1000ft;
      case '1/4mile':
        return m.time14Mile;
      case '1/2mile':
        return m.time12Mile;
      case '0-130mph':
        return m.time0to130mph;
      case '0-200kmh':
        return m.time0to200kmh;
      case '60-130mph':
        return m.time60to130mph;
      case '100-200kmh':
        return m.time100to200kmh;
      default:
        return null;
    }
  }
}

// Convert distance units to meters
double _convertToMeters(double distance, DistanceUnit unit) {
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

    if (prev.speedKmh <= targetSpeedKmh && curr.speedKmh > targetSpeedKmh) {
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
double? _calculateTimeFromHistory(RaceMetrics metrics, OfficialTest test) {
  if (metrics.history.isEmpty) return null;

  if (test.distance != null && test.distanceUnit != null) {
    final targetMeters = _convertToMeters(test.distance!, test.distanceUnit!);
    return _findDistanceCrossingTime(metrics.history, targetMeters);
  } else if (test.endSpeed != null) {
    final start = test.startSpeed ?? 0.0;
    if (start == 0.0) {
      return _findSpeedCrossingTime(metrics.history, test.endSpeed!, 0.0);
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

List<OfficialTest> getCompletedTests(RaceMetrics metrics, {bool showRollout = false}) {
  final List<OfficialTest> completed = [];

  for (final test in officialTests) {
    final time = getCompletedTimeForCategory(metrics, test.id, showRollout: showRollout);
    if (time != null) {
      completed.add(test);
    }
  }

  return completed;
}

double? getCompletedTimeForCategory(RaceMetrics metrics, String categoryId, {bool showRollout = false}) {
  final useRollout = showRollout && metrics.rolloutTime1ft != null;

  // 1. Check if it matches an official test definition
  for (final test in officialTests) {
    if (test.id == categoryId) {
      // Standing start tests require either drag mode or an interval run that started from 0.
      if (test.distance != null ||
          (test.startSpeed != null && test.startSpeed == 0.0)) {
        if (metrics.runMode != 'drag' && metrics.targetStartSpeed != 0.0) {
          return null;
        }
      }

      // Fast path: Check standard precalculated fields
      final precalculated = _getPrecalculatedTime(metrics, test.id, showRollout: useRollout);
      if (precalculated != null) return precalculated;

      // Fallback: Calculate dynamically from history coordinates (always standard non-rollout)
      return _calculateTimeFromHistory(metrics, test);
    }
  }

  // 2. Custom categories lookup
  if (categoryId.startsWith('custom_')) {
    final parts = categoryId.split('_');
    if (parts.length >= 4) {
      final start = double.tryParse(parts[1]);
      final end = double.tryParse(parts[2]);
      final unit = parts[3];

      if (start != null && end != null) {
        double startKmh = start;
        double endKmh = end;
        if (unit == 'mph') {
          startKmh = start / 0.621371;
          endKmh = end / 0.621371;
        }

        if (metrics.runMode == 'interval' &&
            metrics.targetStartSpeed != null &&
            metrics.targetEndSpeed != null &&
            (metrics.targetStartSpeed! - startKmh).abs() < 0.1 &&
            (metrics.targetEndSpeed! - endKmh).abs() < 0.1 &&
            metrics.targetSpeedUnit == unit) {
          final startTime = startKmh == 0.0
              ? 0.0
              : _findSpeedCrossingTime(metrics.history, startKmh, 0.0);
          if (startTime == null) return null;
          final endTime = _findSpeedCrossingTime(
            metrics.history,
            endKmh,
            startTime,
          );
          if (endTime == null) return null;
          double duration = endTime - startTime;
          if (showRollout && startKmh == 0.0 && metrics.rolloutTime1ft != null) {
            duration -= metrics.rolloutTime1ft!;
          }
          return duration;
        }
      }
    }
  }

  return null;
}

String getDisplayLabelForTarget({
  double? distance,
  String? distanceUnit,
  double? startSpeed,
  double? endSpeed,
  String? speedUnit,
  String? runMode,
}) {
  if (runMode == 'drag') {
    if (distance != null && distanceUnit != null) {
      final unit = distanceUnit.toLowerCase();
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
      if (speedUnit == 'mph') {
        final start = (startSpeed / 1.609344).round();
        final end = (endSpeed / 1.609344).round();
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

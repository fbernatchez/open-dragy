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
  final String type; // 'drag' or 'interval'
  final String displayName;
  
  // Criteria
  final double? distance;
  final DistanceUnit? distanceUnit;
  final double? startSpeed; // in km/h
  final double? endSpeed;   // in km/h
  final SpeedUnit? speedUnit;

  const OfficialTest({
    required this.id,
    required this.type,
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
    type: 'drag',
    displayName: '60ft',
    distance: 60.0,
    distanceUnit: DistanceUnit.feet,
  ),
  OfficialTest(
    id: '0-60mph',
    type: 'drag',
    displayName: '0-60 mph',
    startSpeed: 0.0,
    endSpeed: 96.56064, // 60 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '0-100kmh',
    type: 'drag',
    displayName: '0-100 km/h',
    startSpeed: 0.0,
    endSpeed: 100.0,
    speedUnit: SpeedUnit.kmh,
  ),
  OfficialTest(
    id: '1/8mile',
    type: 'drag',
    displayName: '1/8 mile',
    distance: 0.125,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '1000ft',
    type: 'drag',
    displayName: '1000ft',
    distance: 1000.0,
    distanceUnit: DistanceUnit.feet,
  ),
  OfficialTest(
    id: '1/4mile',
    type: 'drag',
    displayName: '1/4 mile',
    distance: 0.25,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '1/2mile',
    type: 'drag',
    displayName: '1/2 mile',
    distance: 0.5,
    distanceUnit: DistanceUnit.mile,
  ),
  OfficialTest(
    id: '0-130mph',
    type: 'drag',
    displayName: '0-130 mph',
    startSpeed: 0.0,
    endSpeed: 209.21472, // 130 mph in km/h
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '0-200kmh',
    type: 'drag',
    displayName: '0-200 km/h',
    startSpeed: 0.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
  // Interval tests
  OfficialTest(
    id: '60-130mph',
    type: 'interval',
    displayName: '60-130 mph',
    startSpeed: 96.56064,
    endSpeed: 209.21472,
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '100-200kmh',
    type: 'interval',
    displayName: '100-200 km/h',
    startSpeed: 100.0,
    endSpeed: 200.0,
    speedUnit: SpeedUnit.kmh,
  ),
  OfficialTest(
    id: '50-75mph',
    type: 'interval',
    displayName: '50-75 mph',
    startSpeed: 80.4672,
    endSpeed: 120.7008,
    speedUnit: SpeedUnit.mph,
  ),
  OfficialTest(
    id: '80-120kmh',
    type: 'interval',
    displayName: '80-120 km/h',
    startSpeed: 80.0,
    endSpeed: 120.0,
    speedUnit: SpeedUnit.kmh,
  ),
];

List<OfficialTest> getCompletedTests(RaceMetrics metrics) {
  final List<OfficialTest> completed = [];
  
  for (final test in officialTests) {
    if (test.type == 'drag') {
      double? time;
      if (test.id == '60ft') time = metrics.time60ft;
      else if (test.id == '0-60mph') time = metrics.time0to60mph;
      else if (test.id == '0-100kmh') time = metrics.time0to100kmh;
      else if (test.id == '1/8mile') time = metrics.time18Mile;
      else if (test.id == '1000ft') time = metrics.time1000ft;
      else if (test.id == '1/4mile') time = metrics.time14Mile;
      else if (test.id == '1/2mile') time = metrics.time12Mile;
      else if (test.id == '0-130mph') time = metrics.time0to130mph;
      else if (test.id == '0-200kmh') time = metrics.time0to200kmh;
      
      if (time != null) {
        completed.add(test);
      }
    } else {
      if (metrics.runMode == 'interval' &&
          metrics.targetStartSpeed != null &&
          metrics.targetEndSpeed != null &&
          (metrics.targetStartSpeed! - test.startSpeed!).abs() < 0.1 &&
          (metrics.targetEndSpeed! - test.endSpeed!).abs() < 0.1 &&
          metrics.targetSpeedUnit == test.speedUnit?.name) {
        
        if (!metrics.isRunning && metrics.history.isNotEmpty && metrics.elapsedTime > 0) {
          completed.add(test);
        }
      }
    }
  }
  
  return completed;
}

double? getCompletedTimeForCategory(RaceMetrics metrics, String categoryId) {
  switch (categoryId) {
    case '60ft':
      return metrics.time60ft;
    case '0-60mph':
      return metrics.time0to60mph;
    case '0-100kmh':
      return metrics.time0to100kmh;
    case '1/8mile':
      return metrics.time18Mile;
    case '1000ft':
      return metrics.time1000ft;
    case '1/4mile':
      return metrics.time14Mile;
    case '1/2mile':
      return metrics.time12Mile;
    case '60-130mph':
      return metrics.time60to130mph;
    case '100-200kmh':
      return metrics.time100to200kmh;
    case '0-130mph':
      return metrics.time0to130mph;
    case '0-200kmh':
      return metrics.time0to200kmh;
    default:
      if (categoryId.startsWith('custom_')) {
        final parts = categoryId.split('_');
        if (parts.length >= 4) {
          final start = double.tryParse(parts[1]);
          final end = double.tryParse(parts[2]);
          final unit = parts[3];
          
          if (metrics.runMode == 'interval' &&
              metrics.targetStartSpeed != null &&
              metrics.targetEndSpeed != null &&
              (metrics.targetStartSpeed! - start!).abs() < 0.1 &&
              (metrics.targetEndSpeed! - end!).abs() < 0.1 &&
              metrics.targetSpeedUnit == unit) {
            return metrics.elapsedTime > 0 ? metrics.elapsedTime : null;
          }
        }
      }
      return null;
  }
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

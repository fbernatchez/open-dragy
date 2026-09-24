import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:open_dragy/models/race_test.dart';

void main() {
  group('Domain Functions: getTestAbsoluteEndTime, trimHistoryToTime, interpolateDataPointAt, getCompletedDistanceForCategory', () {
    // Synthetic run simulating a 1/4 mile run:
    // Car accelerates from 0 to 180 km/h over 10 seconds.
    // Constant acceleration a = 5 m/s^2.
    // Speed: v(t) = 5 * t (m/s) = 18 * t (km/h)
    // Distance: s(t) = 0.5 * 5 * t^2 = 2.5 * t^2 (m)
    // At t = 0.34919s, s = 0.3048 m (1 ft rollout).
    // At 402.336 m (1320 ft), t = sqrt(402.336 / 2.5) = 12.6860s.
    // At 402.6408 m (1321 ft), t = sqrt(402.6408 / 2.5) = 12.6908s.
    // Elevation starts at 100m, drops 1m per second: alt(t) = 100 - t.
    List<DataPoint> generateSyntheticHistory({double duration = 15.0, double dt = 0.1}) {
      final history = <DataPoint>[];
      for (double t = 0.0; t <= duration + 1e-6; t += dt) {
        final speedMs = 5.0 * t;
        final speedKmh = speedMs * 3.6;
        final alt = 100.0 - t;
        history.add(DataPoint(
          elapsedTime: double.parse(t.toStringAsFixed(2)),
          speedKmh: speedKmh,
          gForce: 5.0 / 9.80665,
          altitude: alt,
        ));
      }
      return history;
    }

    final history = generateSyntheticHistory();
    const rollout1ft = 0.34919; // timestamp when car reached 0.3048m

    final quarterMileTest = officialTests.firstWhere((t) => t.id == '1/4mile');
    final zeroToSixtyTest = officialTests.firstWhere((t) => t.id == '0-60mph');
    final sixtyToOneThirtyTest = officialTests.firstWhere((t) => t.id == '60-130mph');

    test('getTestAbsoluteEndTime returns raw absolute crossing time', () {
      final metricsNhra = RaceMetrics(
        speedKmh: 200,
        distanceMeters: 500,
        gForce: 0.5,
        elapsedTime: 15.0,
        history: history,
        rolloutTime1ft: rollout1ft,
      );

      final metricsNonNhra = RaceMetrics(
        speedKmh: 200,
        distanceMeters: 500,
        gForce: 0.5,
        elapsedTime: 15.0,
        history: history,
        rolloutTime1ft: null,
      );

      // 1/4 mile without NHRA: finishes at ~12.686s
      final tEndNonNhra = getTestAbsoluteEndTime(
        metricsNonNhra,
        quarterMileTest,
        useNhraRules: false,
      );
      expect(tEndNonNhra, isNotNull);
      expect(tEndNonNhra!, closeTo(12.686, 0.05));

      // 1/4 mile with NHRA: finishes at ~12.691s (at 1321 ft)
      // Note: Must be absolute timestamp, NOT subtracted by rollout!
      final tEndNhra = getTestAbsoluteEndTime(
        metricsNhra,
        quarterMileTest,
        useNhraRules: true,
      );
      expect(tEndNhra, isNotNull);
      expect(tEndNhra!, closeTo(12.691, 0.05));
      expect(tEndNhra > tEndNonNhra, isTrue); // 1321 ft is further than 1320 ft

      // Standing speed (0-60 mph = 0 - 96.5606 km/h)
      // v = 18*t -> t = 96.5606 / 18 = 5.364s
      final tSpeed = getTestAbsoluteEndTime(
        metricsNhra,
        zeroToSixtyTest,
        useNhraRules: true,
      );
      expect(tSpeed, isNotNull);
      expect(tSpeed!, closeTo(5.364, 0.05));

      // Rolling interval (60-130 mph)
      // 60 mph = 96.56 km/h -> tStart = 5.364s
      // 130 mph = 209.21 km/h -> tEnd = 209.21 / 18 = 11.623s
      final tInterval = getTestAbsoluteEndTime(
        metricsNhra,
        sixtyToOneThirtyTest,
        useNhraRules: true,
      );
      expect(tInterval, isNotNull);
      expect(tInterval!, closeTo(11.623, 0.05));
    });

    test('getTestAbsoluteEndTime returns null for uncompleted / aborted tests', () {
      // Short run of only 3 seconds
      final shortHistory = generateSyntheticHistory(duration: 3.0);
      final metricsShort = RaceMetrics(
        speedKmh: 54,
        distanceMeters: 22.5,
        gForce: 0.5,
        elapsedTime: 3.0,
        history: shortHistory,
      );

      // Quarter mile was never reached
      final tEnd = getTestAbsoluteEndTime(
        metricsShort,
        quarterMileTest,
        useNhraRules: false,
      );
      expect(tEnd, isNull);

      // 0-60 mph was never reached
      final tSpeed = getTestAbsoluteEndTime(
        metricsShort,
        zeroToSixtyTest,
        useNhraRules: false,
      );
      expect(tSpeed, isNull);
    });

    test('getCompletedDistanceForCategory calculates integrated distance without bypass', () {
      final metricsNhra = RaceMetrics(
        speedKmh: 200,
        distanceMeters: 500,
        gForce: 0.5,
        elapsedTime: 15.0,
        history: history,
        rolloutTime1ft: rollout1ft,
      );

      final metricsNonNhra = RaceMetrics(
        speedKmh: 200,
        distanceMeters: 500,
        gForce: 0.5,
        elapsedTime: 15.0,
        history: history,
        rolloutTime1ft: null,
      );

      // Non-NHRA 1/4 mile: integrated distance from 0 to finish ~ 402.34m (1320 ft)
      final distNonNhra = getCompletedDistanceForCategory(
        metricsNonNhra,
        '1/4mile',
        useNhraRules: false,
      );
      expect(distNonNhra, isNotNull);
      expect(distNonNhra!, closeTo(402.34, 0.5));

      // NHRA 1/4 mile: integrated distance from rollout to finish line (1321 ft - 1 ft) ~ 402.34m (1320 ft)
      final distNhra = getCompletedDistanceForCategory(
        metricsNhra,
        '1/4mile',
        useNhraRules: true,
      );
      expect(distNhra, isNotNull);
      expect(distNhra!, closeTo(402.34, 0.5));

      // Uncompleted run returns null
      final shortHistory = generateSyntheticHistory(duration: 3.0);
      final metricsShort = RaceMetrics(
        speedKmh: 54,
        distanceMeters: 22.5,
        gForce: 0.5,
        elapsedTime: 3.0,
        history: shortHistory,
      );
      expect(
        getCompletedDistanceForCategory(metricsShort, '1/4mile', useNhraRules: false),
        isNull,
      );
    });

    test('interpolateDataPointAt produces continuous values at arbitrary timestamps', () {
      final pt = interpolateDataPointAt(history, 5.05); // between 5.0 and 5.1
      expect(pt.elapsedTime, equals(5.05));
      // v(5.05) = 18 * 5.05 = 90.9 km/h
      expect(pt.speedKmh, closeTo(90.9, 0.1));
      // alt(5.05) = 100 - 5.05 = 94.95m
      expect(pt.altitude, closeTo(94.95, 0.05));

      // Boundary tests
      final ptBefore = interpolateDataPointAt(history, -1.0);
      expect(ptBefore.elapsedTime, equals(-1.0));
      expect(ptBefore.speedKmh, equals(history.first.speedKmh));

      final ptAfter = interpolateDataPointAt(history, 20.0);
      expect(ptAfter.elapsedTime, equals(20.0));
      expect(ptAfter.speedKmh, equals(history.last.speedKmh));
    });

    test('trimHistoryToTime correctly trims and appends terminal interpolated DataPoint', () {
      // Trim at 5.05s
      final trimmed = trimHistoryToTime(history, 5.05);
      expect(trimmed.last.elapsedTime, equals(5.05));
      expect(trimmed.last.speedKmh, closeTo(90.9, 0.1));
      expect(trimmed.last.altitude, closeTo(94.95, 0.05));
      expect(trimmed.where((p) => p.elapsedTime > 5.05), isEmpty);

      // Unmodified if endTime is null or >= last point
      expect(identical(trimHistoryToTime(history, null), history), isTrue);
      expect(identical(trimHistoryToTime(history, 20.0), history), isTrue);
    });

    test('findSpeedCrossingTime handles precision snapping and avoids false crossings', () {
      final sampleHistory = [
        DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0, altitude: 100.0),
        DataPoint(elapsedTime: 1.0, speedKmh: 50.0, gForce: 0.5, altitude: 100.0),
        DataPoint(elapsedTime: 2.0, speedKmh: 96.56063999999999, gForce: 0.5, altitude: 100.0), // ~60 mph with IEEE-754 drift
        DataPoint(elapsedTime: 2.5, speedKmh: 100.00005, gForce: 0.3, altitude: 100.0),
        DataPoint(elapsedTime: 3.0, speedKmh: 105.0, gForce: 0.2, altitude: 100.0),
      ];

      const target60MphKmh = 60.0 * 1.609344; // 96.56064 km/h

      // Should snap to exact 2.0s without failing due to float precision
      final t60 = findSpeedCrossingTime(sampleHistory, target60MphKmh, 0.0);
      expect(t60, isNotNull);
      expect(t60, closeTo(2.0, 1e-4));

      // Check false-positive avoidance: searching for 100 km/h after t=2.6s
      // Points at 2.5s (100.00005) and 3.0s (105.0) are both already > 100.0 km/h
      final t100After = findSpeedCrossingTime(sampleHistory, 100.0, 2.5);
      // Since 2.5s is already above 100 and it never crosses 100 again, should return 2.5s or null, never an extrapolated time
      // Starting from 2.5s, prev=100.00005, curr=105.0: both are above 100, no crossing occurs
      expect(t100After, isNull);

      // Deceleration test
      final decelHistory = [
        DataPoint(elapsedTime: 0.0, speedKmh: 120.0, gForce: -0.8, altitude: 100.0),
        DataPoint(elapsedTime: 1.0, speedKmh: 80.0, gForce: -0.8, altitude: 100.0),
        DataPoint(elapsedTime: 2.0, speedKmh: 0.0, gForce: -0.8, altitude: 100.0),
      ];
      final t100Down = findSpeedCrossingTime(decelHistory, 100.0, 0.0, isDecelerating: true);
      expect(t100Down, isNotNull);
      expect(t100Down, closeTo(0.5, 1e-4));
    });
  });
}

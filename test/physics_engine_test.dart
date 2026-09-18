import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/services/physics_engine.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:open_dragy/models/race_test.dart';

RaceMetrics _update(
  PhysicsEngine engine,
  RaceMetrics current,
  double newSpeedKmh,
  double currentAltitude, {
  required bool isArmed,
  required RunMode runMode,
  required String targetLabel,
  required double intervalStartSpeed,
  required double intervalEndSpeed,
}) {
  double? testDistance;
  DistanceUnit? testDistanceUnit;
  double? testStartSpeed;
  double? testEndSpeed;
  SpeedUnit? testSpeedUnit;

  if (runMode == RunMode.drag) {
    if (targetLabel == '1/2 mile') {
      testDistance = 0.5;
      testDistanceUnit = DistanceUnit.mile;
    } else {
      testDistance = 0.25;
      testDistanceUnit = DistanceUnit.mile;
    }
  } else {
    if (targetLabel == '60-130 mph') {
      testStartSpeed = 96.56064;
      testEndSpeed = 209.21472;
      testSpeedUnit = SpeedUnit.mph;
    }
  }

  return engine.updateMetrics(
    current,
    newSpeedKmh,
    currentAltitude,
    isArmed: isArmed,
    runMode: runMode,
    testDistance: testDistance,
    testDistanceUnit: testDistanceUnit,
    testStartSpeed: testStartSpeed,
    testEndSpeed: testEndSpeed,
    testSpeedUnit: testSpeedUnit,
    intervalStartSpeed: intervalStartSpeed,
    intervalEndSpeed: intervalEndSpeed,
  );
}

void main() {
  group('PhysicsEngine Tests', () {
    late PhysicsEngine engine;

    setUp(() {
      engine = PhysicsEngine();
    });

    test('initial state is correct', () {
      final metrics = RaceMetrics();
      expect(metrics.speedKmh, 0.0);
      expect(metrics.distanceMeters, 0.0);
      expect(metrics.elapsedTime, 0.0);
      expect(metrics.isRunning, false);
    });

    test('does not launch if not armed', () {
      RaceMetrics metrics = RaceMetrics();

      // Even if speed goes up to 20 km/h, it should not trigger if not armed
      metrics = _update(engine,
        metrics,
        0.0,
        100.0,
        isArmed: false,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      metrics = _update(engine,
        metrics,
        15.0,
        100.0,
        isArmed: false,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      metrics = _update(engine,
        metrics,
        15.0,
        100.0,
        isArmed: false,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      metrics = _update(engine,
        metrics,
        15.0,
        100.0,
        isArmed: false,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      ); // 3rd time to bypass outlier filter

      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 15.0);
    });

    test('detects launch when speed commits and armed', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        0.1,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        0.4,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        3.2,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.2);
      expect(metrics.elapsedTime, closeTo(0.1, 0.01)); // dt is 0.1
    });

    test('detects launch when speed commits with sudden start', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        0.6,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        1.8,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = _update(engine,
        metrics,
        3.2,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        targetLabel: '1/4 mile',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.2);
    });

    test('detects launch when walking (slow acceleration)', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.3, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.6, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.9, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 1.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 1.5, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 1.8, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 2.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 2.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 2.7, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);

      expect(metrics.isRunning, false);

      metrics = _update(engine,metrics, 3.3, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.3);
      expect(metrics.elapsedTime, closeTo(0.8333, 0.01));
    });

    test('integrates distance properly during run', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 3.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      final initialDistance = metrics.distanceMeters;

      // Next step to 6.2 km/h
      metrics = _update(engine,metrics, 6.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);

      final expectedDeltaDistance = ((3.2 / 3.6) + (6.2 / 3.6)) / 2 * 0.1;
      expect(metrics.distanceMeters, closeTo(initialDistance + expectedDeltaDistance, 0.001));
      expect(metrics.elapsedTime, closeTo(0.2, 0.01));
    });

    test('rejects outliers and resets after sustained mismatch', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);

      final beforeOutlier = metrics;
      
      metrics = _update(engine,metrics, 10.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147); // 1st outlier
      expect(metrics.speedKmh, beforeOutlier.speedKmh); // Should be unchanged

      metrics = _update(engine,metrics, 10.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147); // 2nd outlier (accepted because delta=0)
      expect(metrics.speedKmh, 10.0); // Accepts new speed because it stabilized
    });

    test('does not launch if reset while moving', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 3.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      // Reset the run manually
      metrics = engine.reset();
      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 0.0);

      // Next GPS sample is still 30.0 km/h (need 3 to bypass filter)
      metrics = _update(engine,metrics, 30.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 30.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 30.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      
      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 30.0);
    });

    test('calculates correct overall slope for the run', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 3.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);

      expect(metrics.startAltitude, 100.0);

      for (int i = 1; i <= 15; i++) {
        double currentAlt = 100.0 - (i * 0.1); // drops 0.1m per 0.1s step
        metrics = _update(engine,metrics, 60.0, currentAlt, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      }
      
      final double startAlt = metrics.startAltitude ?? 0.0;
      final double endAlt = metrics.history.isNotEmpty
          ? (metrics.history.last.altitude ?? startAlt)
          : startAlt;
      final double elevationDiff = endAlt - startAlt;
      final double avgSlope = metrics.distanceMeters > 0
          ? (elevationDiff / metrics.distanceMeters) * 100
          : 0.0;

      expect(avgSlope, lessThan(0.0));
      expect(avgSlope, closeTo(-7.17, 0.1));
    });

    test('triggers drag milestones and completes at target 1/2 mile', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/2 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.5, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/2 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 3.5, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/2 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      double altitude = 100.0;
      double speed = 10.0;
      
      while (metrics.isRunning && speed <= 220.0) {
        speed += 10.0;
        metrics = _update(engine,metrics, speed, altitude, isArmed: true, runMode: RunMode.drag, targetLabel: '1/2 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      }

      while (metrics.isRunning) {
        metrics = _update(engine,metrics, 220.0, altitude, isArmed: true, runMode: RunMode.drag, targetLabel: '1/2 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      }

      // Verify that all timers were triggered
      expect(metrics.testTimes['60ft'], isNotNull);
      expect(metrics.testTimes['0-60mph'], isNotNull);
      expect(metrics.testTimes['0-100kmh'], isNotNull);
      expect(metrics.testTimes['1/8mile'], isNotNull);
      expect(metrics.testTimes['1000ft'], isNotNull);
      expect(metrics.testTimes['1/4mile'], isNotNull);
      expect(metrics.testTimes['1/2mile'], isNotNull);
      expect(metrics.testTimes['60-130mph'], isNotNull);
      expect(metrics.testTimes['100-200kmh'], isNotNull);
      expect(metrics.testTimes['0-130mph'], isNotNull);
      expect(metrics.testTimes['0-200kmh'], isNotNull);
      expect(metrics.isRunning, false); // completed 1/2 mile
    });

    test('detects interval run launch, integrates, and completes at target 60-130 mph', () {
      RaceMetrics metrics = RaceMetrics();

      // Arm in interval mode and accelerate gradually below start speed
      double speed = 50.0;
      while (speed <= 95.0) {
        metrics = _update(engine,
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          targetLabel: '60-130 mph',
          intervalStartSpeed: 96.5606,
          intervalEndSpeed: 209.2147,
        );
        speed += 3.0;
      }
      expect(metrics.isRunning, false);

      // Speed crosses 60 mph (96.5606 km/h) -> Trigger!
      metrics = _update(engine,
        metrics,
        98.0, // crosses 96.5606 from 95.0
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        targetLabel: '60-130 mph',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      // elapsedTime should be the start fraction
      expect(metrics.elapsedTime, closeTo(0.048, 0.01)); 

      // Accelerate towards 130 mph (209.2147 km/h)
      speed = 98.0;
      while (metrics.isRunning && speed <= 208.0) {
        speed += 3.0;
        metrics = _update(engine,
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          targetLabel: '60-130 mph',
          intervalStartSpeed: 96.5606,
          intervalEndSpeed: 209.2147,
        );
      }
      expect(metrics.isRunning, true);

      // Crosses 130 mph -> Finish!
      metrics = _update(engine,
        metrics,
        210.0, // crosses 209.2147
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        targetLabel: '60-130 mph',
        intervalStartSpeed: 96.5606,
        intervalEndSpeed: 209.2147,
      );

      expect(metrics.isRunning, false);
      expect(metrics.testTimes['60-130mph'], isNotNull);
    });

    test('cancels interval run if speed drops', () {
      RaceMetrics metrics = RaceMetrics();

      // Trigger start gradually
      double speed = 80.0;
      while (speed <= 95.0) {
        metrics = _update(engine,metrics, speed, 100.0, isArmed: true, runMode: RunMode.interval, targetLabel: '60-130 mph', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
        speed += 3.0;
      }
      metrics = _update(engine,metrics, 98.0, 100.0, isArmed: true, runMode: RunMode.interval, targetLabel: '60-130 mph', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      // Speed drops below start speed - 10 km/h (below 86.56 km/h) for 20 ticks
      for (int i = 0; i < 20; i++) {
        metrics = _update(engine,metrics, 80.0, 100.0, isArmed: true, runMode: RunMode.interval, targetLabel: '60-130 mph', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      }

      // Should cancel and isRunning should become false
      expect(metrics.isRunning, false);
    });

    test('preserves run distance, elapsed time, and start altitude of completed run when stationary', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = _update(engine,metrics, 0.0, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.1, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 0.4, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      metrics = _update(engine,metrics, 3.2, 100.0, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      double currentAltitude = 100.0;
      for (int i = 0; i < 150; i++) {
        currentAltitude += 0.1;
        metrics = _update(engine,metrics, 100.0, currentAltitude, isArmed: true, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);
      }
      expect(metrics.isRunning, false);
      expect(metrics.history.isNotEmpty, true);

      final double completedDistance = metrics.distanceMeters;
      final double completedElapsedTime = metrics.elapsedTime;
      final double completedStartAltitude = metrics.startAltitude!;

      // Stationary speed = 0.0, disarmed
      metrics = _update(engine,metrics, 0.0, 150.0, isArmed: false, runMode: RunMode.drag, targetLabel: '1/4 mile', intervalStartSpeed: 96.5606, intervalEndSpeed: 209.2147);

      // Verify stats are preserved!
      expect(metrics.isRunning, false);
      expect(metrics.distanceMeters, completedDistance);
      expect(metrics.elapsedTime, completedElapsedTime);
      expect(metrics.startAltitude, completedStartAltitude);
    });

    test('does not calculate drag milestones for interval runs but calculates target interval milestone', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm in interval mode and run a 50-75 mph target
      // startSpeed: 50 mph = 80.4672 km/h
      // endSpeed: 75 mph = 120.7008 km/h
      
      double speed = 75.0;
      while (speed <= 125.0) {
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 50.0,
          testEndSpeed: 75.0,
          testSpeedUnit: SpeedUnit.mph,
          intervalStartSpeed: 80.4672,
          intervalEndSpeed: 120.7008,
        );
        speed += 3.0;
      }
      expect(metrics.isRunning, false);
      expect(metrics.elapsedTime, greaterThan(0.0));
      
      // Verify that getCompletedTimeForCategory for drag milestones returns null
      expect(getCompletedTimeForCategory(metrics, '60ft'), isNull);
      expect(getCompletedTimeForCategory(metrics, '0-60mph'), isNull);
      
      // Since 50-75mph was removed from official tests, it should return null via getCompletedTimeForCategory
      expect(getCompletedTimeForCategory(metrics, '50-75mph'), isNull);
    });

    test('standing-start interval run triggers and completes correctly', () {
      RaceMetrics metrics = RaceMetrics();
      // Custom 0-50 mph target
      // startSpeed: 0.0 mph = 0.0 km/h
      // endSpeed: 50.0 mph = 80.4672 km/h
      
      // Arm in interval mode and keep speed at 0
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      expect(metrics.isRunning, false);

      // Accelerate slightly (below launchCommitThreshold)
      metrics = engine.updateMetrics(
        metrics,
        1.5,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      expect(metrics.isRunning, false);

      // Accelerate above launchCommitThreshold (3.0 km/h) -> Trigger!
      metrics = engine.updateMetrics(
        metrics,
        4.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      expect(metrics.isRunning, true);

      // Accelerate further up to endSpeed
      double speed = 4.0;
      while (metrics.isRunning) {
        speed += 3.0;
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 50.0,
          testSpeedUnit: SpeedUnit.mph,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 80.4672,
        );
      }
      expect(metrics.isRunning, false);
      expect(metrics.elapsedTime, greaterThan(0.0));
      expect(metrics.rolloutTime1ft, isNotNull);

      final rawTime = getCompletedTimeForCategory(
        metrics,
        'custom_0_50_mph',
        useNhraRules: false,
      );
      final nhraTime = getCompletedTimeForCategory(
        metrics,
        'custom_0_50_mph',
        useNhraRules: true,
      );
      expect(rawTime, isNotNull);
      expect(nhraTime, isNotNull);
      expect(nhraTime!, lessThan(rawTime!));
      expect(nhraTime, closeTo(rawTime - metrics.rolloutTime1ft!, 0.001));
    });

    test('standing-start interval run cancels when speed drops below 3 km/h', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm and trigger standing start
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      metrics = engine.updateMetrics(
        metrics,
        1.5,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      metrics = engine.updateMetrics(
        metrics,
        4.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      expect(metrics.isRunning, true);

      // Drops below 3.0 km/h for 20 ticks (2 seconds)
      for (int i = 0; i < 20; i++) {
        metrics = engine.updateMetrics(
          metrics,
          1.5,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 50.0,
          testSpeedUnit: SpeedUnit.mph,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 80.4672,
        );
      }
      expect(metrics.isRunning, false);
    });

    test('getCompletedTimeForCategory calculates custom interval category with mph unit conversion', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm, trigger, and complete custom 0-50 mph run
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      metrics = engine.updateMetrics(
        metrics,
        3.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      metrics = engine.updateMetrics(
        metrics,
        5.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 80.4672,
      );
      expect(metrics.isRunning, true);

      double speed = 5.0;
      while (metrics.isRunning) {
        speed += 3.0;
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 50.0,
          testSpeedUnit: SpeedUnit.mph,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 80.4672,
        );
      }
      expect(metrics.isRunning, false);

      final customTest = const RaceTest(
        id: 'custom_0_50_mph',
        displayName: '0-50 mph',
        startSpeed: 0.0,
        endSpeed: 80.4672,
        speedUnit: SpeedUnit.mph,
        isOfficial: false,
      );
      final time = getCompletedTimeForCategory(metrics, 'custom_0_50_mph', activeTests: [customTest]);
      expect(time, isNotNull);
      expect(time, closeTo(metrics.elapsedTime, 0.01));
    });

    test('getCompletedTimeForCategory calculates custom interval category for 0-160 kmh and 0-100 mph', () {
      RaceMetrics metricsMph = RaceMetrics();
      // Arm, trigger, and complete custom 0-100 mph run (160.9344 km/h)
      metricsMph = engine.updateMetrics(
        metricsMph,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 100.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.9344,
      );
      metricsMph = engine.updateMetrics(
        metricsMph,
        3.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 100.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.9344,
      );
      metricsMph = engine.updateMetrics(
        metricsMph,
        5.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 100.0,
        testSpeedUnit: SpeedUnit.mph,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.9344,
      );
      expect(metricsMph.isRunning, true);

      double speedKmhMph = 5.0;
      while (metricsMph.isRunning) {
        speedKmhMph += 3.0;
        metricsMph = engine.updateMetrics(
          metricsMph,
          speedKmhMph,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 100.0,
          testSpeedUnit: SpeedUnit.mph,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 160.9344,
        );
      }
      expect(metricsMph.isRunning, false);
      final target100mph = const RaceTest(
        id: 'custom_0_100_mph',
        displayName: '0-100 mph',
        startSpeed: 0.0,
        endSpeed: 160.9344,
        speedUnit: SpeedUnit.mph,
        isOfficial: false,
      );
      final timeMph = getCompletedTimeForCategory(metricsMph, 'custom_0_100_mph', activeTests: [target100mph]);
      expect(timeMph, isNotNull);
      expect(timeMph, closeTo(metricsMph.elapsedTime, 0.01));

      RaceMetrics metricsKmh = RaceMetrics();
      // Arm, trigger, and complete custom 0-160 km/h run (160.0 km/h)
      metricsKmh = engine.updateMetrics(
        metricsKmh,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 160.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.0,
      );
      metricsKmh = engine.updateMetrics(
        metricsKmh,
        3.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 160.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.0,
      );
      metricsKmh = engine.updateMetrics(
        metricsKmh,
        5.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 160.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 160.0,
      );
      expect(metricsKmh.isRunning, true);

      double speedKmh = 5.0;
      while (metricsKmh.isRunning) {
        speedKmh += 3.0;
        metricsKmh = engine.updateMetrics(
          metricsKmh,
          speedKmh,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 160.0,
          testSpeedUnit: SpeedUnit.kmh,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 160.0,
        );
      }
      expect(metricsKmh.isRunning, false);
      final target160 = const RaceTest(
        id: 'custom_0_160_kmh',
        displayName: '0-160 km/h',
        startSpeed: 0.0,
        endSpeed: 160.0,
        speedUnit: SpeedUnit.kmh,
        isOfficial: false,
      );
      final timeKmh = getCompletedTimeForCategory(metricsKmh, 'custom_0_160_kmh', activeTests: [target160]);
      expect(timeKmh, isNotNull);
      expect(timeKmh, closeTo(metricsKmh.elapsedTime, 0.01));
    });

    test('uses dynamic dt from GPS timestamps instead of static 0.1s', () {
      RaceMetrics metrics = RaceMetrics();

      // Send gradual samples to populate the speed buffer and avoid outlier rejection
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
        gpsTimeSeconds: 999.8,
      );

      metrics = engine.updateMetrics(
        metrics,
        0.2,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
        gpsTimeSeconds: 999.9,
      );

      metrics = engine.updateMetrics(
        metrics,
        0.6,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
        gpsTimeSeconds: 1000.0,
      );

      // Trigger launch at speed = 4.0 km/h with GPS time = 1000.2s (delta of 0.2s)
      metrics = engine.updateMetrics(
        metrics,
        4.0,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
        gpsTimeSeconds: 1000.2,
      );

      expect(metrics.isRunning, true);
      // Because crossing was interpolated in a 0.2s step, elapsedTime should reflect currentDt = 0.2s
      // The crossing is between 0.2 km/h (index 1) and 0.6 km/h (index 2).
      // startFraction = (0.5 - 0.2) / (0.6 - 0.2) = 0.75
      // elapsedOffset = (3 - 1 - 0.75) * 0.2 = 1.25 * 0.2 = 0.25s
      expect(metrics.elapsedTime, closeTo(0.25, 0.001));

      // Next speed update is 6.5 km/h with GPS time = 1000.5s (delta of 0.3s)
      metrics = engine.updateMetrics(
        metrics,
        6.5,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
        gpsTimeSeconds: 1000.5,
      );

      // elapsedTime should increase by currentDt = 0.3s
      // New elapsedTime = 0.25 + 0.3 = 0.55s
      expect(metrics.elapsedTime, closeTo(0.55, 0.001));
    });

    test('standing-start interval run 0-200 km/h sets precalculated fields', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm and trigger standing start for 0-200 km/h
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 200.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 200.0,
      );
      expect(metrics.isRunning, false);

      // Accelerate slightly below launchCommitThreshold (to avoid outlier rejection)
      metrics = engine.updateMetrics(
        metrics,
        2.5,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 200.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 200.0,
      );
      expect(metrics.isRunning, false);

      // Accelerate above launchCommitThreshold (3.0 km/h) -> Trigger!
      metrics = engine.updateMetrics(
        metrics,
        5.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 0.0,
        testEndSpeed: 200.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 200.0,
      );
      expect(metrics.isRunning, true);

      // Accelerate to 200.0 km/h
      double speed = 5.0;
      while (metrics.isRunning) {
        speed += 3.0;
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 0.0,
          testEndSpeed: 200.0,
          testSpeedUnit: SpeedUnit.kmh,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 200.0,
        );
      }
      expect(metrics.isRunning, false);
      expect(metrics.testTimes['0-200kmh'], isNotNull, reason: 'time0to200kmh is null! testStartSpeed: ${metrics.testStartSpeed}, testEndSpeed: ${metrics.testEndSpeed}, testSpeedUnit: ${metrics.testSpeedUnit}, elapsedTime: ${metrics.elapsedTime}, speedKmh: ${metrics.speedKmh}, isRunning: ${metrics.isRunning}');
      expect(metrics.testTimes['0-200kmh'], closeTo(metrics.elapsedTime, 0.01));
    });

    test('rollout calculation and fallback logic', () {
      // 1. Simulate a run with rollout data
      RaceMetrics metricsWithRollout = RaceMetrics(
        runMode: RunMode.drag,
        testTimes: {'0-60mph': 4.5, '0-60mph_rollout': 4.2},
        rolloutTime1ft: 0.3,
      );

      // When rollout is enabled, retrieve rollout time
      expect(
        getCompletedTimeForCategory(metricsWithRollout, '0-60mph', useNhraRules: true),
        4.2,
      );

      // When rollout is disabled, retrieve standard time
      expect(
        getCompletedTimeForCategory(metricsWithRollout, '0-60mph', useNhraRules: false),
        4.5,
      );

      // 2. Simulate an old run without rollout data (rolloutTime1ft is null)
      RaceMetrics metricsOldRun = RaceMetrics(
        runMode: RunMode.drag,
        testTimes: {'0-60mph': 4.5},
        rolloutTime1ft: null,
      );

      expect(
        getCompletedTimeForCategory(metricsOldRun, '0-60mph', useNhraRules: true),
        4.5,
      );

      // 3. Custom category with rollout
      RaceMetrics customMetrics = RaceMetrics(
        runMode: RunMode.interval,
        testStartSpeed: 0.0,
        testEndSpeed: 80.4672, // 50 mph
        testSpeedUnit: SpeedUnit.mph,
        rolloutTime1ft: 0.3,
        history: [
          const DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0),
          const DataPoint(elapsedTime: 1.0, speedKmh: 40.0, gForce: 0.0),
          const DataPoint(elapsedTime: 2.0, speedKmh: 85.0, gForce: 0.0),
        ],
      );

      final customTest = const RaceTest(
        id: 'custom_0_50_mph',
        displayName: '0-50 mph',
        startSpeed: 0.0,
        endSpeed: 80.4672,
        speedUnit: SpeedUnit.mph,
        isOfficial: false,
      );

      // Without rollout
      expect(
        getCompletedTimeForCategory(customMetrics, 'custom_0_50_mph', useNhraRules: false, activeTests: [customTest]),
        closeTo(1.89, 0.01), // crossing speed is around 1.89s
      );

      // With rollout (should subtract rolloutTime1ft)
      expect(
        getCompletedTimeForCategory(customMetrics, 'custom_0_50_mph', useNhraRules: true, activeTests: [customTest]),
        closeTo(1.89 - 0.3, 0.01),
      );

      // Custom category old run (without rolloutTime1ft)
      RaceMetrics customMetricsOld = RaceMetrics(
        runMode: RunMode.interval,
        testStartSpeed: 0.0,
        testEndSpeed: 50.0,
        testSpeedUnit: SpeedUnit.mph,
        rolloutTime1ft: null,
        history: [
          const DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0),
          const DataPoint(elapsedTime: 1.0, speedKmh: 40.0, gForce: 0.0),
          const DataPoint(elapsedTime: 2.0, speedKmh: 85.0, gForce: 0.0),
        ],
      );

      expect(
        getCompletedTimeForCategory(customMetricsOld, 'custom_0_50_mph', useNhraRules: true, activeTests: [customTest]),
        closeTo(1.89, 0.01),
      );
    });
    test('braking interval run triggers, integrates, completes, and cancels correctly', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm 100-0 km/h braking test
      metrics = engine.updateMetrics(
        metrics,
        110.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      expect(metrics.isRunning, false); // Speed is 110.0, not triggered yet

      // Speed drops to 90.0, triggering the run
      metrics = engine.updateMetrics(
        metrics,
        90.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      expect(metrics.isRunning, true);
      
      // Speed drops further
      metrics = engine.updateMetrics(
        metrics,
        50.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      expect(metrics.isRunning, true);

      // Speed crosses 0 to complete the run
      metrics = engine.updateMetrics(
        metrics,
        -5.0, // negative speed simulating zero crossing
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      expect(metrics.isRunning, false);
      expect(metrics.elapsedTime, greaterThan(0.0));
      
      // Test cancellation logic (should cancel if speed increases by 10 above start)
      RaceMetrics metricsCancel = RaceMetrics();
      metricsCancel = engine.updateMetrics(
        metricsCancel,
        105.0,
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      metricsCancel = engine.updateMetrics(
        metricsCancel,
        95.0, // Triggers run
        100.0,
        isArmed: true,
        runMode: RunMode.interval,
        testDistance: null,
        testDistanceUnit: null,
        testStartSpeed: 100.0,
        testEndSpeed: 0.0,
        testSpeedUnit: SpeedUnit.kmh,
        intervalStartSpeed: 100.0,
        intervalEndSpeed: 0.0,
      );
      expect(metricsCancel.isRunning, true);
      
      // Speed increases back above 110 (100 + 10) for 3 seconds (30 ticks)
      for (int i = 0; i < 30; i++) {
        metricsCancel = engine.updateMetrics(
          metricsCancel,
          115.0,
          100.0,
          isArmed: true,
          runMode: RunMode.interval,
          testDistance: null,
          testDistanceUnit: null,
          testStartSpeed: 100.0,
          testEndSpeed: 0.0,
          testSpeedUnit: SpeedUnit.kmh,
          intervalStartSpeed: 100.0,
          intervalEndSpeed: 0.0,
        );
      }
      expect(metricsCancel.isRunning, false); // Cancelled
    });

    test('drag run does not falsely trigger braking test during acceleration', () {
      RaceMetrics metrics = RaceMetrics();
      // Arm 1/4 mile drag run
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: RunMode.drag,
        testDistance: 0.25,
        testDistanceUnit: DistanceUnit.mile,
        testStartSpeed: null,
        testEndSpeed: null,
        testSpeedUnit: null,
        intervalStartSpeed: 0.0,
        intervalEndSpeed: 0.0,
      );

      // Accelerate from 0 to 120 km/h (crossing 100 km/h upwards)
      for (double speed = 1.0; speed <= 120.0; speed += 5.0) {
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.drag,
          testDistance: 0.25,
          testDistanceUnit: DistanceUnit.mile,
          testStartSpeed: null,
          testEndSpeed: null,
          testSpeedUnit: null,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 0.0,
        );
      }

      // During acceleration, 100-0kmh and 60-0mph must NOT be completed or negative
      expect(metrics.testTimes.containsKey('100-0kmh'), false);
      expect(metrics.testTimes.containsKey('60-0mph'), false);

      final timeNonNhra = getCompletedTimeForCategory(metrics, '100-0kmh', useNhraRules: false);
      final timeNhra = getCompletedTimeForCategory(metrics, '100-0kmh', useNhraRules: true);
      expect(timeNonNhra, null);
      expect(timeNhra, null);

      // Now simulate vehicle braking from 120 km/h down to 0 km/h
      for (double speed = 110.0; speed >= 0.0; speed -= 10.0) {
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: RunMode.drag,
          testDistance: 0.25,
          testDistanceUnit: DistanceUnit.mile,
          testStartSpeed: null,
          testEndSpeed: null,
          testSpeedUnit: null,
          intervalStartSpeed: 0.0,
          intervalEndSpeed: 0.0,
        );
      }

      // After braking, 100-0 km/h should be recorded with a positive time
      expect(metrics.testTimes.containsKey('100-0kmh'), true);
      expect(metrics.testTimes['100-0kmh']!, greaterThan(0.0));
      expect(getCompletedTimeForCategory(metrics, '100-0kmh', useNhraRules: false), greaterThan(0.0));
    });

    test('calculateTimeFromHistory calculates valid duration from data points', () {
      final metricsWithoutPrecalc = RaceMetrics(
        runMode: RunMode.drag,
        testTimes: {},
        history: [
          const DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0),
          const DataPoint(elapsedTime: 2.0, speedKmh: 105.0, gForce: 0.0), // accelerated past 100
          const DataPoint(elapsedTime: 4.0, speedKmh: 105.0, gForce: 0.0), // start braking
          const DataPoint(elapsedTime: 5.0, speedKmh: 95.0, gForce: 0.0),  // crossed 100 downwards at t~4.5
          const DataPoint(elapsedTime: 7.0, speedKmh: 0.0, gForce: 0.0),   // reached 0 at t=7.0
        ],
      );

      // Calculates from history (7.0 - 4.5 = 2.5s)
      final calculated = getCompletedTimeForCategory(metricsWithoutPrecalc, '100-0kmh', useNhraRules: false);
      expect(calculated, isNotNull);
      expect(calculated, closeTo(2.5, 0.1));
    });

    test('getCompletedTests does not duplicate official preset tests as custom interval tests', () {
      final history = [
        const DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0),
        const DataPoint(elapsedTime: 0.25, speedKmh: 10.0, gForce: 0.5),
        const DataPoint(elapsedTime: 3.5, speedKmh: 100.0, gForce: 0.8),
      ];
      final metrics = RaceMetrics(
        runMode: RunMode.interval,
        testStartSpeed: 0.0,
        testEndSpeed: 60.0,
        testSpeedUnit: SpeedUnit.mph,
        history: history,
      );

      final completed = getCompletedTests(metrics);
      final count0to60 = completed.where((t) => t.displayName == '0-60 mph').length;
      expect(count0to60, 1);
    });

    test('matchesUnitSystem filters custom distance tests correctly between metric and imperial', () {
      const custom100ft = RaceTest(
        id: 'custom_dist_100_feet',
        displayName: '100ft',
        distance: 100.0,
        distanceUnit: DistanceUnit.feet,
        isOfficial: false,
      );
      const custom100m = RaceTest(
        id: 'custom_dist_100_meter',
        displayName: '100m',
        distance: 100.0,
        distanceUnit: DistanceUnit.meter,
        isOfficial: false,
      );

      // 100ft should NOT match metric, but should match imperial
      expect(custom100ft.matchesUnitSystem(true), isFalse);
      expect(custom100ft.matchesUnitSystem(false), isTrue);

      // 100m should match metric, but NOT imperial
      expect(custom100m.matchesUnitSystem(true), isTrue);
      expect(custom100m.matchesUnitSystem(false), isFalse);

      // getReachedMilestones should not include 100ft when isMetric is true
      final metrics = RaceMetrics(
        runMode: RunMode.drag,
        distanceMeters: 50.0,
        testTimes: {'custom_dist_100_feet': 2.0},
      );
      final milestonesMetric = getReachedMilestones(
        metrics,
        isMetric: true,
        useNhraRules: false,
        customTests: [custom100ft],
        isTestEnabled: (_) => true,
      );
      expect(milestonesMetric.any((m) => m.label == '100ft'), isFalse);

      final milestonesImperial = getReachedMilestones(
        metrics,
        isMetric: false,
        useNhraRules: false,
        customTests: [custom100ft],
        isTestEnabled: (_) => true,
      );
      expect(milestonesImperial.any((m) => m.label == '100ft'), isTrue);
    });
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/services/physics_engine.dart';
import 'package:open_dragy/models/race_metrics.dart';

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
      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: false,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      metrics = engine.updateMetrics(
        metrics,
        15.0,
        100.0,
        isArmed: false,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );

      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 15.0);
    });

    test('detects launch when speed commits and armed', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        0.1,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        0.4,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        3.2,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.2);
      expect(metrics.elapsedTime, closeTo(0.1, 0.01)); // dt is 0.1
    });

    test('detects launch when speed commits with sudden start', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(
        metrics,
        0.0,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        0.6,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        1.8,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(
        metrics,
        3.2,
        100.0,
        isArmed: true,
        runMode: 'drag',
        targetLabel: '1/4 mile',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.2);
    });

    test('detects launch when walking (slow acceleration)', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.3, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.6, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.9, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 1.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 1.5, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 1.8, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 2.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 2.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 2.7, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);

      expect(metrics.isRunning, false);

      metrics = engine.updateMetrics(metrics, 3.3, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);
      expect(metrics.speedKmh, 3.3);
      expect(metrics.elapsedTime, closeTo(0.8333, 0.01));
    });

    test('integrates distance properly during run', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 3.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      final initialDistance = metrics.distanceMeters;

      // Next step to 6.2 km/h
      metrics = engine.updateMetrics(metrics, 6.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);

      final expectedDeltaDistance = ((3.2 / 3.6) + (6.2 / 3.6)) / 2 * 0.1;
      expect(metrics.distanceMeters, closeTo(initialDistance + expectedDeltaDistance, 0.001));
      expect(metrics.elapsedTime, closeTo(0.2, 0.01));
    });

    test('rejects outliers and resets after sustained mismatch', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);

      final beforeOutlier = metrics;
      
      metrics = engine.updateMetrics(metrics, 10.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147); // 1st outlier
      expect(metrics.speedKmh, beforeOutlier.speedKmh); // Should be unchanged

      metrics = engine.updateMetrics(metrics, 10.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147); // 2nd outlier
      expect(metrics.speedKmh, beforeOutlier.speedKmh); // Should be unchanged

      metrics = engine.updateMetrics(metrics, 10.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147); // 3rd outlier (> 2) -> resets counter, clears buffer
      expect(metrics.speedKmh, 10.0); // Accepts new speed, displays it
    });

    test('does not launch if reset while moving', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 3.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      // Reset the run manually
      metrics = engine.reset();
      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 0.0);

      // Next GPS sample is still 30.0 km/h
      metrics = engine.updateMetrics(metrics, 30.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      
      expect(metrics.isRunning, false);
      expect(metrics.speedKmh, 30.0);
    });

    test('calculates correct overall slope for the run', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 3.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);

      expect(metrics.startAltitude, 100.0);

      for (int i = 1; i <= 15; i++) {
        double currentAlt = 100.0 - (i * 0.1); // drops 0.1m per 0.1s step
        metrics = engine.updateMetrics(metrics, 60.0, currentAlt, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
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

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/2 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.5, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/2 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 3.5, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/2 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      double altitude = 100.0;
      double speed = 10.0;
      
      while (metrics.isRunning && speed <= 220.0) {
        speed += 10.0;
        metrics = engine.updateMetrics(metrics, speed, altitude, isArmed: true, runMode: 'drag', targetLabel: '1/2 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      }

      while (metrics.isRunning) {
        metrics = engine.updateMetrics(metrics, 220.0, altitude, isArmed: true, runMode: 'drag', targetLabel: '1/2 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      }

      // Verify that all timers were triggered
      expect(metrics.time60ft, isNotNull);
      expect(metrics.time0to60mph, isNotNull);
      expect(metrics.time0to100kmh, isNotNull);
      expect(metrics.time18Mile, isNotNull);
      expect(metrics.time1000ft, isNotNull);
      expect(metrics.time14Mile, isNotNull);
      expect(metrics.time12Mile, isNotNull);
      expect(metrics.trap12Mile, isNotNull);
      expect(metrics.time60to130mph, isNotNull);
      expect(metrics.time100to200kmh, isNotNull);
      expect(metrics.time0to130mph, isNotNull);
      expect(metrics.time0to200kmh, isNotNull);
      expect(metrics.isRunning, false); // completed 1/2 mile
    });

    test('detects rolling run launch, integrates, and completes at target 60-130 mph', () {
      RaceMetrics metrics = RaceMetrics();

      // Arm in rolling mode and accelerate gradually below start speed
      double speed = 50.0;
      while (speed <= 95.0) {
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: 'rolling',
          targetLabel: '60-130 mph',
          rollingStartSpeed: 96.5606,
          rollingEndSpeed: 209.2147,
        );
        speed += 3.0;
      }
      expect(metrics.isRunning, false);

      // Speed crosses 60 mph (96.5606 km/h) -> Trigger!
      metrics = engine.updateMetrics(
        metrics,
        98.0, // crosses 96.5606 from 95.0
        100.0,
        isArmed: true,
        runMode: 'rolling',
        targetLabel: '60-130 mph',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );
      expect(metrics.isRunning, true);
      // elapsedTime should be the start fraction
      expect(metrics.elapsedTime, closeTo(0.048, 0.01)); 

      // Accelerate towards 130 mph (209.2147 km/h)
      speed = 98.0;
      while (metrics.isRunning && speed <= 208.0) {
        speed += 3.0;
        metrics = engine.updateMetrics(
          metrics,
          speed,
          100.0,
          isArmed: true,
          runMode: 'rolling',
          targetLabel: '60-130 mph',
          rollingStartSpeed: 96.5606,
          rollingEndSpeed: 209.2147,
        );
      }
      expect(metrics.isRunning, true);

      // Crosses 130 mph -> Finish!
      metrics = engine.updateMetrics(
        metrics,
        210.0, // crosses 209.2147
        100.0,
        isArmed: true,
        runMode: 'rolling',
        targetLabel: '60-130 mph',
        rollingStartSpeed: 96.5606,
        rollingEndSpeed: 209.2147,
      );

      expect(metrics.isRunning, false);
      expect(metrics.time60to130mph, isNotNull);
    });

    test('cancels rolling run if speed drops', () {
      RaceMetrics metrics = RaceMetrics();

      // Trigger start gradually
      double speed = 80.0;
      while (speed <= 95.0) {
        metrics = engine.updateMetrics(metrics, speed, 100.0, isArmed: true, runMode: 'rolling', targetLabel: '60-130 mph', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
        speed += 3.0;
      }
      metrics = engine.updateMetrics(metrics, 98.0, 100.0, isArmed: true, runMode: 'rolling', targetLabel: '60-130 mph', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      // Speed drops below start speed - 10 km/h (below 86.56 km/h) for 20 ticks
      for (int i = 0; i < 20; i++) {
        metrics = engine.updateMetrics(metrics, 80.0, 100.0, isArmed: true, runMode: 'rolling', targetLabel: '60-130 mph', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      }

      // Should cancel and isRunning should become false
      expect(metrics.isRunning, false);
    });

    test('preserves run distance, elapsed time, and start altitude of completed run when stationary', () {
      RaceMetrics metrics = RaceMetrics();

      metrics = engine.updateMetrics(metrics, 0.0, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.1, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 0.4, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      metrics = engine.updateMetrics(metrics, 3.2, 100.0, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      expect(metrics.isRunning, true);

      double currentAltitude = 100.0;
      for (int i = 0; i < 150; i++) {
        currentAltitude += 0.1;
        metrics = engine.updateMetrics(metrics, 100.0, currentAltitude, isArmed: true, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);
      }
      expect(metrics.isRunning, false);
      expect(metrics.history.isNotEmpty, true);

      final double completedDistance = metrics.distanceMeters;
      final double completedElapsedTime = metrics.elapsedTime;
      final double completedStartAltitude = metrics.startAltitude!;

      // Stationary speed = 0.0, disarmed
      metrics = engine.updateMetrics(metrics, 0.0, 150.0, isArmed: false, runMode: 'drag', targetLabel: '1/4 mile', rollingStartSpeed: 96.5606, rollingEndSpeed: 209.2147);

      // Verify stats are preserved!
      expect(metrics.isRunning, false);
      expect(metrics.distanceMeters, completedDistance);
      expect(metrics.elapsedTime, completedElapsedTime);
      expect(metrics.startAltitude, completedStartAltitude);
    });
  });
}

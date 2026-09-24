import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:open_dragy/models/race_test.dart';
import 'package:open_dragy/models/saved_run.dart';
import 'package:open_dragy/providers/dragy_provider.dart';
import 'package:open_dragy/screens/run_detail_screen.dart';

class MockDragyProvider extends ChangeNotifier implements DragyProvider {
  @override
  bool isMetric = false; // Imperial: feet, mph

  @override
  bool useNhraRules = true;

  @override
  bool tempInCelsius = false;

  @override
  List<RaceTest> customTests = [];

  @override
  List<SavedRun> savedRuns = [];

  @override
  bool isTestEnabled(String testId) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RunDetailScreen Distance, Graph & Scrubbing Widget Tests', () {
    // Generate synthetic 1/4 mile run with overshoot:
    // Car reaches 1320 ft at t = 12.686s, 1321 ft at t = 12.691s.
    // GPS kept recording until t = 13.5s (overshoot to 1500 ft / 450 m).
    List<DataPoint> generateRunHistory() {
      final history = <DataPoint>[];
      for (double t = 0.0; t <= 13.5 + 1e-6; t += 0.1) {
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

    testWidgets('Displays accurate 1320.0 ft distance instead of overshot GPS distance', (tester) async {
      final mockProvider = MockDragyProvider();
      final history = generateRunHistory();

      // GPS total distance is 455.6 m (1495 ft) due to trailing ticks
      final run = SavedRun(
        id: 'test_quarter_mile_run',
        dateTime: DateTime.now(),
        metrics: RaceMetrics(
          runMode: RunMode.drag,
          testDistance: 0.25,
          testDistanceUnit: DistanceUnit.mile,
          speedKmh: 243.0,
          distanceMeters: 455.6,
          elapsedTime: 13.5,
          rolloutTime1ft: 0.35,
          history: history,
        ),
      );

      mockProvider.savedRuns = [run];

      await tester.pumpWidget(
        ChangeNotifierProvider<DragyProvider>.value(
          value: mockProvider,
          child: MaterialApp(home: RunDetailScreen(run: run)),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to reveal summary
      await tester.ensureVisible(find.text('Run Summary'));
      await tester.pumpAndSettle();

      // The raw GPS distance was 1494.8 ft (455.6 m)
      // The calculated distance should be ~1320.0 ft (402.3 m)
      expect(find.text('1320.0 ft'), findsOneWidget);
      expect(find.text('1494.8 ft'), findsNothing);
    });

    testWidgets('Incomplete run falls back gracefully to recorded GPS distance', (tester) async {
      final mockProvider = MockDragyProvider();

      // Aborted run at 2.0s
      final shortHistory = [
        const DataPoint(elapsedTime: 0.0, speedKmh: 0.0, gForce: 0.0, altitude: 50.0),
        const DataPoint(elapsedTime: 1.0, speedKmh: 20.0, gForce: 0.4, altitude: 50.1),
        const DataPoint(elapsedTime: 2.0, speedKmh: 35.0, gForce: 0.3, altitude: 50.2),
      ];

      final run = SavedRun(
        id: 'test_aborted_run',
        dateTime: DateTime.now(),
        metrics: RaceMetrics(
          runMode: RunMode.drag,
          testDistance: 0.25,
          testDistanceUnit: DistanceUnit.mile,
          speedKmh: 35.0,
          distanceMeters: 15.0,
          elapsedTime: 2.0,
          history: shortHistory,
        ),
      );

      mockProvider.savedRuns = [run];

      await tester.pumpWidget(
        ChangeNotifierProvider<DragyProvider>.value(
          value: mockProvider,
          child: MaterialApp(home: RunDetailScreen(run: run)),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to summary
      await tester.ensureVisible(find.text('Run Summary'));
      await tester.pumpAndSettle();

      // 15.0m in feet is 49.2 ft
      expect(find.text('49.2 ft'), findsOneWidget);
      // Telemetry chart is rendered with untrimmed points
      expect(find.byType(TelemetryChart), findsOneWidget);
    });

    testWidgets('Scrubbing chart displays continuous LIVE scrubbing telemetry HUD', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockProvider = MockDragyProvider();
      final history = generateRunHistory();

      final run = SavedRun(
        id: 'test_scrubbing_run',
        dateTime: DateTime.now(),
        metrics: RaceMetrics(
          runMode: RunMode.drag,
          testDistance: 0.25,
          testDistanceUnit: DistanceUnit.mile,
          speedKmh: 243.0,
          distanceMeters: 455.6,
          elapsedTime: 13.5,
          rolloutTime1ft: 0.35,
          history: history,
        ),
      );

      mockProvider.savedRuns = [run];

      await tester.pumpWidget(
        ChangeNotifierProvider<DragyProvider>.value(
          value: mockProvider,
          child: MaterialApp(home: RunDetailScreen(run: run)),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure chart is visible
      await tester.ensureVisible(find.byType(TelemetryChart));
      await tester.pumpAndSettle();

      // Before scrubbing: shows default summary
      expect(find.text('TELEMETRY GRAPH'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);

      // Locate the exact CustomPaint that uses TelemetryChartPainter
      final chartPainterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TelemetryChartPainter,
      );
      expect(chartPainterFinder, findsOneWidget);

      final chartCenter = tester.getCenter(chartPainterFinder);
      final gesture = await tester.startGesture(chartCenter);
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      // During scrub: shows LIVE indicator and Scrubbing Telemetry
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Scrubbing Telemetry'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      // After release: returns to TELEMETRY GRAPH
      expect(find.text('TELEMETRY GRAPH'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
    });
  });
}

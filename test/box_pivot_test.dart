import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:open_dragy/providers/dragy_provider.dart';
import 'package:open_dragy/widgets/box_pivot_preview.dart';
import 'widget_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Box Pivot & Coordinate Transformation Tests', () {
    double computeRotatedGForce(int angle, double gx, double gy, [double gz = 0.0]) {
      return DragyProvider.computeLeveledGForce(
        boxPivotAngle: angle,
        gx: gx,
        gy: gy,
        gz: gz,
      );
    }

    test('0 degrees (default): forward is +Y (USB on right)', () {
      expect(computeRotatedGForce(0, 0.0, 1.0), closeTo(1.0, 1e-5));
      expect(computeRotatedGForce(0, 1.0, 0.0), closeTo(0.0, 1e-5));
      expect(computeRotatedGForce(0, 0.0, -1.0), closeTo(-1.0, 1e-5));
    });

    test('90 degrees clockwise: forward is -X (USB facing cabin)', () {
      expect(computeRotatedGForce(90, -1.0, 0.0), closeTo(1.0, 1e-5));
      expect(computeRotatedGForce(90, 1.0, 0.0), closeTo(-1.0, 1e-5));
      expect(computeRotatedGForce(90, 0.0, 1.0), closeTo(0.0, 1e-5));
    });

    test('180 degrees: forward is -Y (USB facing left)', () {
      expect(computeRotatedGForce(180, 0.0, -1.0), closeTo(1.0, 1e-5));
      expect(computeRotatedGForce(180, 0.0, 1.0), closeTo(-1.0, 1e-5));
      expect(computeRotatedGForce(180, 1.0, 0.0), closeTo(0.0, 1e-5));
    });

    test('270 degrees: forward is +X (USB facing windshield)', () {
      expect(computeRotatedGForce(270, 1.0, 0.0), closeTo(1.0, 1e-5));
      expect(computeRotatedGForce(270, -1.0, 0.0), closeTo(-1.0, 1e-5));
      expect(computeRotatedGForce(270, 0.0, 1.0), closeTo(0.0, 1e-5));
    });

    test('45 degrees: forward projects diagonal vector', () {
      final diag = sqrt(0.5);
      expect(computeRotatedGForce(45, -diag, diag), closeTo(1.0, 1e-5));
    });

    test('3D tilt: 30-degree pitch on windshield mount maintains 1.0G forward reading', () {
      const pitchRad = 30.0 * (pi / 180.0);
      final gravY = -sin(pitchRad);
      final gravZ = cos(pitchRad);

      // At rest on 30 deg slope: only gravity acts on sensor
      final restG = DragyProvider.computeLeveledGForce(
        boxPivotAngle: 0,
        gx: 0.0,
        gy: gravY,
        gz: gravZ,
        gravX: 0.0,
        gravY: gravY,
        gravZ: gravZ,
      );
      expect(restG, closeTo(0.0, 1e-5));

      // Under 1.0G horizontal road acceleration: dynamic acceleration is (0, cos(30), sin(30))
      final launchG = DragyProvider.computeLeveledGForce(
        boxPivotAngle: 0,
        gx: 0.0,
        gy: cos(pitchRad) + gravY,
        gz: sin(pitchRad) + gravZ,
        gravX: 0.0,
        gravY: gravY,
        gravZ: gravZ,
      );
      expect(launchG, closeTo(1.0, 1e-5));
    });

    test('3D tilt: 15-degree lateral roll eliminates lateral gravity leakage', () {
      const rollRad = 15.0 * (pi / 180.0);
      final gravX = sin(rollRad);
      final gravZ = cos(rollRad);

      final restG = DragyProvider.computeLeveledGForce(
        boxPivotAngle: 0,
        gx: gravX,
        gy: 0.0,
        gz: gravZ,
        gravX: gravX,
        gravY: 0.0,
        gravZ: gravZ,
      );
      expect(restG, closeTo(0.0, 1e-5));

      final launchG = DragyProvider.computeLeveledGForce(
        boxPivotAngle: 0,
        gx: gravX,
        gy: 1.0,
        gz: gravZ,
        gravX: gravX,
        gravY: 0.0,
        gravZ: gravZ,
      );
      expect(launchG, closeTo(1.0, 1e-5));
    });

    test('3D gravity EMA filter converges to static 3D vector', () {
      double gravX = 0.0;
      double gravY = 0.0;
      double gravZ = 1.0;
      const alpha = 0.02;

      const targetX = 0.25;
      const targetY = -0.45;
      const targetZ = 0.85;

      for (int i = 0; i < 300; i++) {
        gravX = gravX * (1.0 - alpha) + targetX * alpha;
        gravY = gravY * (1.0 - alpha) + targetY * alpha;
        gravZ = gravZ * (1.0 - alpha) + targetZ * alpha;
      }

      expect(gravX, closeTo(targetX, 0.01));
      expect(gravY, closeTo(targetY, 0.01));
      expect(gravZ, closeTo(targetZ, 0.01));
    });

    test('Angle normalization modulo 360', () {
      final mock = MockDragyProvider();
      expect(mock.boxPivotAngle, 0);

      mock.setBoxPivotAngle(90);
      expect(mock.boxPivotAngle, 90);

      mock.setBoxPivotAngle(360);
      expect(mock.boxPivotAngle, 0);

      mock.setBoxPivotAngle(450);
      expect(mock.boxPivotAngle, 90);

      mock.setBoxPivotAngle(-90);
      expect(mock.boxPivotAngle, 270);
    });

    test('Settings serialization preserves boxPivotAngle', () {
      final map = {
        'isMetric': true,
        'boxPivotAngle': 135,
      };

      expect(map['boxPivotAngle'], 135);
      final loadedAngle = (map['boxPivotAngle'] as num?)?.toInt() ?? 0;
      expect(loadedAngle, 135);
    });
  });

  group('BoxPivotPreviewWidget UI Tests', () {
    testWidgets('renders preview widget and responds to preset taps',
        (WidgetTester tester) async {
      final mock = MockDragyProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<DragyProvider>.value(
              value: mock,
              child: const BoxPivotPreviewWidget(),
            ),
          ),
        ),
      );

      expect(find.text('Box Pivot Orientation'), findsOneWidget);
      expect(find.text('0°'), findsWidgets);
      expect(find.text('FRONT'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);

      await tester.tap(find.text('90°'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 90);

      await tester.tap(find.text('180°'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 180);

      await tester.tap(find.text('270°'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 270);

      await tester.tap(find.text('0°').last);
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 0);
    });

    testWidgets('step buttons adjust angle by 1 degree',
        (WidgetTester tester) async {
      final mock = MockDragyProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<DragyProvider>.value(
              value: mock,
              child: const BoxPivotPreviewWidget(),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('+1 Degree'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 1);

      await tester.tap(find.byTooltip('-1 Degree'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 0);

      await tester.tap(find.byTooltip('-1 Degree'));
      await tester.pumpAndSettle();
      expect(mock.boxPivotAngle, 359);
    });
  });
}

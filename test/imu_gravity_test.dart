import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/imu_gravity.dart';

void main() {
  group('GravityVector', () {
    test('average returns null for empty samples', () {
      expect(GravityVector.average(const []), isNull);
    });

    test('average computes component means', () {
      final avg = GravityVector.average(const [
        GravityVector(-0.10, -0.08, 1.00),
        GravityVector(-0.12, -0.10, 1.01),
      ]);
      expect(avg, isNotNull);
      expect(avg!.x, closeTo(-0.11, 1e-9));
      expect(avg.y, closeTo(-0.09, 1e-9));
      expect(avg.z, closeTo(1.005, 1e-9));
    });
  });

  group('LinearAcceleration', () {
    test('without gravity passes raw values through', () {
      final linear = LinearAcceleration.fromRaw(ax: 0.1, ay: 0.2, az: 1.0);
      expect(linear.y, 0.2);
    });

    test('with gravity subtracts full vector', () {
      const gravity = GravityVector(-0.11, -0.09, 1.00);
      final linear = LinearAcceleration.fromRaw(
        ax: 0.0,
        ay: 0.0,
        az: 1.0,
        gravity: gravity,
      );
      expect(linear.x, closeTo(0.11, 1e-9));
      expect(linear.y, closeTo(0.09, 1e-9));
      expect(linear.z, closeTo(0.0, 1e-9));
    });
  });
}

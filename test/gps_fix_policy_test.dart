import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/services/gps_fix_policy.dart';

void main() {
  group('GpsFixPolicy', () {
    test('accepts a valid 3D PVT fix with enough satellites', () {
      expect(
        GpsFixPolicy.accepts(
          valid: true,
          fixType: 3,
          satellites: 4,
          usedPvt: true,
        ),
        isTrue,
      );
    });

    test('rejects invalid, non-3D, sparse, and non-PVT fixes', () {
      expect(
        GpsFixPolicy.accepts(
          valid: false,
          fixType: 3,
          satellites: 12,
          usedPvt: true,
        ),
        isFalse,
      );
      expect(
        GpsFixPolicy.accepts(
          valid: true,
          fixType: 2,
          satellites: 12,
          usedPvt: true,
        ),
        isFalse,
      );
      expect(
        GpsFixPolicy.accepts(
          valid: true,
          fixType: 3,
          satellites: 3,
          usedPvt: true,
        ),
        isFalse,
      );
      expect(
        GpsFixPolicy.accepts(
          valid: true,
          fixType: 3,
          satellites: 12,
          usedPvt: false,
        ),
        isFalse,
      );
    });
  });
}

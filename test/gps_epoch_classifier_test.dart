import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/services/gps_epoch_classifier.dart';

void main() {
  group('GpsEpochClassifier', () {
    test('accepts the first and subsequent ordered epochs', () {
      expect(
        GpsEpochClassifier.classify(
          previousAcceptedMs: null,
          currentMs: 1000,
        ).status,
        GpsEpochStatus.first,
      );

      final ordered = GpsEpochClassifier.classify(
        previousAcceptedMs: 1000,
        currentMs: 1050,
      );
      expect(ordered.status, GpsEpochStatus.accepted);
      expect(ordered.deltaMs, 50);
      expect(ordered.shouldProcess, isTrue);
    });

    test('rejects duplicate and out-of-order epochs', () {
      final duplicate = GpsEpochClassifier.classify(
        previousAcceptedMs: 1000,
        currentMs: 1000,
      );
      expect(duplicate.status, GpsEpochStatus.duplicate);
      expect(duplicate.shouldProcess, isFalse);

      final outOfOrder = GpsEpochClassifier.classify(
        previousAcceptedMs: 1000,
        currentMs: 950,
      );
      expect(outOfOrder.status, GpsEpochStatus.outOfOrder);
      expect(outOfOrder.shouldProcess, isFalse);
    });

    test('only treats a negative delta near the week boundary as rollover', () {
      final rollover = GpsEpochClassifier.classify(
        previousAcceptedMs: GpsEpochClassifier.gpsWeekMs - 25,
        currentMs: 25,
      );
      expect(rollover.status, GpsEpochStatus.weekRollover);
      expect(rollover.deltaMs, 50);
      expect(rollover.shouldProcess, isTrue);
    });

    test('marks a real transport gap and retains its actual duration', () {
      final gap = GpsEpochClassifier.classify(
        previousAcceptedMs: 1000,
        currentMs: 1500,
      );
      expect(gap.status, GpsEpochStatus.gap);
      expect(gap.deltaMs, 500);
      expect(gap.shouldProcess, isTrue);
    });
  });
}

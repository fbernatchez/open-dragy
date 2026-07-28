enum GpsEpochStatus {
  first,
  accepted,
  gap,
  duplicate,
  outOfOrder,
  weekRollover,
}

class GpsEpochDecision {
  final GpsEpochStatus status;
  final int? deltaMs;

  const GpsEpochDecision(this.status, this.deltaMs);

  bool get shouldProcess =>
      status != GpsEpochStatus.duplicate && status != GpsEpochStatus.outOfOrder;
}

/// Classifies u-blox iTOW epochs without depending on BLE delivery time.
class GpsEpochClassifier {
  static const int gpsWeekMs = 604800000;
  static const int defaultGapThresholdMs = 150;
  static const int rolloverWindowMs = 60000;

  static GpsEpochDecision classify({
    required int? previousAcceptedMs,
    required int currentMs,
    int gapThresholdMs = defaultGapThresholdMs,
  }) {
    if (previousAcceptedMs == null) {
      return const GpsEpochDecision(GpsEpochStatus.first, null);
    }

    final rawDelta = currentMs - previousAcceptedMs;
    if (rawDelta == 0) {
      return const GpsEpochDecision(GpsEpochStatus.duplicate, null);
    }

    if (rawDelta < 0) {
      final isWeekRollover =
          previousAcceptedMs >= gpsWeekMs - rolloverWindowMs &&
          currentMs <= rolloverWindowMs;
      if (!isWeekRollover) {
        return const GpsEpochDecision(GpsEpochStatus.outOfOrder, null);
      }
      return GpsEpochDecision(
        GpsEpochStatus.weekRollover,
        rawDelta + gpsWeekMs,
      );
    }

    return GpsEpochDecision(
      rawDelta > gapThresholdMs ? GpsEpochStatus.gap : GpsEpochStatus.accepted,
      rawDelta,
    );
  }
}

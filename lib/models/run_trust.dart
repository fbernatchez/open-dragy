import 'raw_run_log.dart';

/// GPS quality snapshot for a saved run (Dragy-class trust).
enum RunTrustLevel {
  /// PVT + tight hAcc/sAcc + enough sats.
  high,

  /// Usable for timing, not perfect.
  medium,

  /// Weak / NMEA-only / noisy speed accuracy.
  low,

  /// Older runs without trust fields.
  unknown,
}

class RunTrust {
  final double? avgHAccM;
  final double? minHAccM;
  final double? avgSAccMps;
  final double? maxSAccMps;
  final double? avgNumSV;
  final bool? usedPvt;
  final RunTrustLevel level;

  const RunTrust({
    this.avgHAccM,
    this.minHAccM,
    this.avgSAccMps,
    this.maxSAccMps,
    this.avgNumSV,
    this.usedPvt,
    required this.level,
  });

  bool get hasMetrics =>
      avgHAccM != null || avgSAccMps != null || avgNumSV != null;

  String get shortLabel {
    switch (level) {
      case RunTrustLevel.high:
        return 'Trust A';
      case RunTrustLevel.medium:
        return 'Trust B';
      case RunTrustLevel.low:
        return 'Trust C';
      case RunTrustLevel.unknown:
        return 'Trust —';
    }
  }

  /// Green / amber / red for history badge.
  int get colorArgb {
    switch (level) {
      case RunTrustLevel.high:
        return 0xFF39FF14;
      case RunTrustLevel.medium:
        return 0xFFFFBF00;
      case RunTrustLevel.low:
        return 0xFFFF5252;
      case RunTrustLevel.unknown:
        return 0x99FFFFFF;
    }
  }

  Map<String, dynamic> toJson() => {
        'avgHAccM': avgHAccM,
        'minHAccM': minHAccM,
        'avgSAccMps': avgSAccMps,
        'maxSAccMps': maxSAccMps,
        'avgNumSV': avgNumSV,
        'usedPvt': usedPvt,
        'level': level.name,
      };

  factory RunTrust.fromJson(Map<String, dynamic> json) {
    final levelName = json['level'] as String?;
    final level = RunTrustLevel.values.firstWhere(
      (e) => e.name == levelName,
      orElse: () => RunTrustLevel.unknown,
    );
    return RunTrust(
      avgHAccM: (json['avgHAccM'] as num?)?.toDouble(),
      minHAccM: (json['minHAccM'] as num?)?.toDouble(),
      avgSAccMps: (json['avgSAccMps'] as num?)?.toDouble(),
      maxSAccMps: (json['maxSAccMps'] as num?)?.toDouble(),
      avgNumSV: (json['avgNumSV'] as num?)?.toDouble(),
      usedPvt: json['usedPvt'] as bool?,
      level: level,
    );
  }

  /// Aggregate from raw GPS around the timed run (prefer post-start samples).
  static RunTrust? fromRawGps(
    List<RawGpsSample>? gps, {
    int? runStartElapsedMs,
  }) {
    if (gps == null || gps.isEmpty) return null;

    Iterable<RawGpsSample> samples = gps;
    if (runStartElapsedMs != null) {
      final during = gps.where((s) => s.elapsedMs >= runStartElapsedMs);
      if (during.isNotEmpty) samples = during;
    }

    final hAccs = <double>[];
    final sAccs = <double>[];
    final sats = <double>[];
    var pvtTrue = 0;
    var pvtKnown = 0;

    for (final s in samples) {
      final h = s.hAccM;
      if (h != null && h > 0 && h < 100) hAccs.add(h);
      final a = s.sAccMps;
      if (a != null && a > 0 && a < 50) sAccs.add(a);
      final n = s.satellites;
      if (n != null && n > 0) sats.add(n.toDouble());
      pvtKnown++;
      if (s.usedPvt) pvtTrue++;
    }

    if (hAccs.isEmpty && sAccs.isEmpty && sats.isEmpty) return null;

    final avgH = hAccs.isEmpty
        ? null
        : hAccs.reduce((a, b) => a + b) / hAccs.length;
    final minH = hAccs.isEmpty ? null : hAccs.reduce((a, b) => a < b ? a : b);
    final avgS = sAccs.isEmpty
        ? null
        : sAccs.reduce((a, b) => a + b) / sAccs.length;
    final maxS = sAccs.isEmpty ? null : sAccs.reduce((a, b) => a > b ? a : b);
    final avgSv =
        sats.isEmpty ? null : sats.reduce((a, b) => a + b) / sats.length;
    final usedPvt = pvtKnown == 0 ? null : (pvtTrue * 2 >= pvtKnown);

    return RunTrust(
      avgHAccM: avgH,
      minHAccM: minH,
      avgSAccMps: avgS,
      maxSAccMps: maxS,
      avgNumSV: avgSv,
      usedPvt: usedPvt,
      level: classify(
        avgHAccM: avgH,
        maxSAccMps: maxS,
        avgNumSV: avgSv,
        usedPvt: usedPvt,
      ),
    );
  }

  static RunTrustLevel classify({
    double? avgHAccM,
    double? maxSAccMps,
    double? avgNumSV,
    bool? usedPvt,
  }) {
    if (avgHAccM == null && maxSAccMps == null && avgNumSV == null) {
      return RunTrustLevel.unknown;
    }
    final h = avgHAccM ?? 99.0;
    final s = maxSAccMps ?? 99.0;
    final sv = avgNumSV ?? 0.0;
    final pvt = usedPvt ?? false;

    if (pvt && h <= 3.0 && s <= 0.5 && sv >= 8) {
      return RunTrustLevel.high;
    }
    if ((pvt || h <= 5.0) && h <= 5.0 && s <= 1.0 && sv >= 6) {
      return RunTrustLevel.medium;
    }
    return RunTrustLevel.low;
  }
}

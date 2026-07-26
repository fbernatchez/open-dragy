import 'dart:typed_data';

/// Compact GPS fix from OpenDragy firmware (UBX-NAV-PVT derived).
class OdgpFix {
  final int version;
  final int fixType;
  final int flags;
  final int numSV;
  final int iTOW;
  final double latitude;
  final double longitude;
  final double altitudeM;
  final double speedKmh;
  final double headingDeg;
  final double hAccM;
  final double vAccM;
  final double sAccMps;
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  const OdgpFix({
    required this.version,
    required this.fixType,
    required this.flags,
    required this.numSV,
    required this.iTOW,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.speedKmh,
    required this.headingDeg,
    required this.hAccM,
    required this.vAccM,
    required this.sAccMps,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  bool get gnssFixOk => (flags & 0x01) != 0;
  bool get is3d => fixType >= 3;
  bool get valid => gnssFixOk && fixType >= 2;

  /// UTC time-of-day seconds (for physics dt), same role as NMEA RMC time.
  double get timeSeconds => hour * 3600 + minute * 60 + second.toDouble();

  /// Rough HDOP-like figure for legacy UI (hAcc metres / ~5 m).
  double get hdopApprox => hAccM > 0 ? (hAccM / 5.0).clamp(0.1, 99.0) : 99.0;
}

/// ODGP v1 binary packet (52 bytes, little-endian).
class OdgpParser {
  OdgpParser._();

  static const int packetSize = 52;

  /// Accuracies above ~100 km are u-blox "unknown" sentinels, not real metres.
  static double _accMmToM(int mm) {
    if (mm == 0 || mm >= 100000000) return 0.0;
    return mm / 1000.0;
  }

  static OdgpFix? tryParse(List<int> bytes) {
    if (bytes.length < packetSize) return null;
    if (bytes[0] != 0x4F || // O
        bytes[1] != 0x44 || // D
        bytes[2] != 0x47 || // G
        bytes[3] != 0x50) {
      // P
      return null;
    }
    final bd = ByteData.sublistView(Uint8List.fromList(bytes), 0, packetSize);
    final version = bd.getUint8(4);
    if (version != 1) return null;

    final gSpeedMmS = bd.getInt32(24, Endian.little);
    final headMot = bd.getInt32(28, Endian.little);
    final hAccMm = bd.getUint32(32, Endian.little);
    final vAccMm = bd.getUint32(36, Endian.little);
    final sAccMmS = bd.getUint32(40, Endian.little);

    return OdgpFix(
      version: version,
      fixType: bd.getUint8(5),
      flags: bd.getUint8(6),
      numSV: bd.getUint8(7),
      iTOW: bd.getUint32(8, Endian.little),
      longitude: bd.getInt32(12, Endian.little) * 1e-7,
      latitude: bd.getInt32(16, Endian.little) * 1e-7,
      altitudeM: bd.getInt32(20, Endian.little) / 1000.0,
      speedKmh: (gSpeedMmS / 1000.0) * 3.6,
      headingDeg: headMot * 1e-5,
      // u-blox often reports 0xFFFFFFFF mm when no fix — treat as unknown.
      hAccM: _accMmToM(hAccMm),
      vAccM: _accMmToM(vAccMm),
      sAccMps: _accMmToM(sAccMmS),
      year: bd.getUint16(44, Endian.little),
      month: bd.getUint8(46),
      day: bd.getUint8(47),
      hour: bd.getUint8(48),
      minute: bd.getUint8(49),
      second: bd.getUint8(50),
    );
  }
}

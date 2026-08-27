import 'dart:typed_data';

class UbxNavPvt {
  final int iTOW; // GPS time of week of the navigation epoch (ms)
  final int year; // Year (UTC)
  final int month; // Month, range 1..12 (UTC)
  final int day; // Day of month, range 1..31 (UTC)
  final int hour; // Hour of day, range 0..23 (UTC)
  final int min; // Minute of hour, range 0..59 (UTC)
  final int sec; // Seconds of minute, range 0..60 (UTC)
  final int valid; // Validity flags
  final int tAcc; // Time accuracy estimate (ns)
  final int nano; // Fraction of second, range -1e9 .. 1e9 (ns)
  final int fixType; // GNSSfix Type
  final int flags; // Fix status flags
  final int flags2; // Additional flags
  final int numSV; // Number of satellites used in Nav Solution
  final double lon; // Longitude (deg)
  final double lat; // Latitude (deg)
  final double height; // Height above ellipsoid (m)
  final double hMSL; // Height above mean sea level (m)
  final double hAcc; // Horizontal accuracy estimate (m)
  final double vAcc; // Vertical accuracy estimate (m)
  final double velN; // NED north velocity (m/s)
  final double velE; // NED east velocity (m/s)
  final double velD; // NED down velocity (m/s)
  final double gSpeed; // Ground Speed (2-D) (m/s)
  final double headMot; // Heading of motion (2-D) (deg)
  final double sAcc; // Speed accuracy estimate (m/s)
  final double headAcc; // Heading accuracy estimate (deg)
  final double pDOP; // Position DOP
  
  UbxNavPvt({
    required this.iTOW,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.min,
    required this.sec,
    required this.valid,
    required this.tAcc,
    required this.nano,
    required this.fixType,
    required this.flags,
    required this.flags2,
    required this.numSV,
    required this.lon,
    required this.lat,
    required this.height,
    required this.hMSL,
    required this.hAcc,
    required this.vAcc,
    required this.velN,
    required this.velE,
    required this.velD,
    required this.gSpeed,
    required this.headMot,
    required this.sAcc,
    required this.headAcc,
    required this.pDOP,
  });

  factory UbxNavPvt.fromBytes(List<int> bytes) {
    // Note: The payload starts after Header(2), Class(1), ID(1), Length(2).
    // So the payload itself starts at index 6 in the full UBX frame.
    // We assume 'bytes' here is just the payload (e.g. 92 or 100 bytes).
    
    // Dart doesn't have an easy Struct view, so we parse manually using ByteData.
    // It's little-endian.
    
    final bd = ByteData.view(Uint8List.fromList(bytes).buffer);
    
    return UbxNavPvt(
      iTOW: bd.getUint32(0, Endian.little),
      year: bd.getUint16(4, Endian.little),
      month: bd.getUint8(6),
      day: bd.getUint8(7),
      hour: bd.getUint8(8),
      min: bd.getUint8(9),
      sec: bd.getUint8(10),
      valid: bd.getUint8(11),
      tAcc: bd.getUint32(12, Endian.little),
      nano: bd.getInt32(16, Endian.little),
      fixType: bd.getUint8(20),
      flags: bd.getUint8(21),
      flags2: bd.getUint8(22),
      numSV: bd.getUint8(23),
      lon: bd.getInt32(24, Endian.little) / 10000000.0,
      lat: bd.getInt32(28, Endian.little) / 10000000.0,
      height: bd.getInt32(32, Endian.little) / 1000.0,
      hMSL: bd.getInt32(36, Endian.little) / 1000.0,
      hAcc: bd.getUint32(40, Endian.little) / 1000.0,
      vAcc: bd.getUint32(44, Endian.little) / 1000.0,
      velN: bd.getInt32(48, Endian.little) / 1000.0,
      velE: bd.getInt32(52, Endian.little) / 1000.0,
      velD: bd.getInt32(56, Endian.little) / 1000.0,
      gSpeed: bd.getInt32(60, Endian.little) / 1000.0,
      headMot: bd.getInt32(64, Endian.little) / 100000.0,
      sAcc: bd.getUint32(68, Endian.little) / 1000.0,
      headAcc: bd.getUint32(72, Endian.little) / 100000.0,
      pDOP: bd.getUint16(76, Endian.little) / 100.0,
    );
  }
}

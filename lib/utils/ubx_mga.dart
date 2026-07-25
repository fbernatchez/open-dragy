import 'dart:typed_data';

/// Minimal u-blox UBX-MGA-INI builders for cold-start aiding (M10).
class UbxMga {
  UbxMga._();

  static const int _classMga = 0x13;
  static const int _idIni = 0x40;

  /// UBX-MGA-INI-TIME_UTC — phone UTC with conservative accuracy.
  static Uint8List timeUtc(
    DateTime utc, {
    int accuracySeconds = 5,
  }) {
    final t = utc.toUtc();
    final payload = ByteData(24);
    payload.setUint8(0, 0x10); // type
    payload.setUint8(1, 0x00); // version
    payload.setUint8(2, 0x00); // ref: apply on receipt
    payload.setInt8(3, -128); // leapSecs unknown
    payload.setUint16(4, t.year, Endian.little);
    payload.setUint8(6, t.month);
    payload.setUint8(7, t.day);
    payload.setUint8(8, t.hour);
    payload.setUint8(9, t.minute);
    payload.setUint8(10, t.second);
    payload.setUint8(11, 0x00); // bitfield0: untrusted
    payload.setUint32(12, t.millisecond * 1000000, Endian.little); // ns
    payload.setUint16(16, accuracySeconds.clamp(0, 0xffff), Endian.little);
    payload.setUint8(18, 0);
    payload.setUint8(19, 0);
    payload.setUint32(20, 0, Endian.little); // tAccNs
    return _frame(_classMga, _idIni, payload.buffer.asUint8List());
  }

  /// UBX-MGA-INI-POS_LLH — coarse WGS84 position.
  /// [posAccMeters] is stddev; keep large if the fix may be stale.
  static Uint8List posLlh({
    required double latitudeDeg,
    required double longitudeDeg,
    double altitudeMeters = 0,
    double posAccMeters = 50000,
  }) {
    final payload = ByteData(20);
    payload.setUint8(0, 0x01); // type
    payload.setUint8(1, 0x00); // version
    payload.setUint8(2, 0);
    payload.setUint8(3, 0);
    payload.setInt32(4, (latitudeDeg * 1e7).round(), Endian.little);
    payload.setInt32(8, (longitudeDeg * 1e7).round(), Endian.little);
    payload.setInt32(12, (altitudeMeters * 100).round(), Endian.little); // cm
    final accCm = (posAccMeters * 100).round().clamp(1, 0x7fffffff);
    payload.setUint32(16, accCm, Endian.little);
    return _frame(_classMga, _idIni, payload.buffer.asUint8List());
  }

  /// Position accuracy that grows with age of the last known fix.
  static double accuracyMetersForAge(Duration age) {
    if (age.inHours < 6) return 5000; // 5 km
    if (age.inDays < 2) return 20000;
    if (age.inDays < 14) return 50000;
    return 100000;
  }

  static Uint8List _frame(int msgClass, int msgId, Uint8List payload) {
    final len = payload.length;
    final packet = Uint8List(8 + len);
    packet[0] = 0xB5;
    packet[1] = 0x62;
    packet[2] = msgClass;
    packet[3] = msgId;
    packet[4] = len & 0xff;
    packet[5] = (len >> 8) & 0xff;
    packet.setRange(6, 6 + len, payload);

    var ckA = 0;
    var ckB = 0;
    // Checksum over class, id, length, payload (not sync bytes).
    for (var i = 2; i < 6 + len; i++) {
      ckA = (ckA + packet[i]) & 0xff;
      ckB = (ckB + ckA) & 0xff;
    }
    packet[6 + len] = ckA;
    packet[7 + len] = ckB;
    return packet;
  }
}

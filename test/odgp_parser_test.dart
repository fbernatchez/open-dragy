import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/odgp_parser.dart';

void main() {
  test('OdgpParser decodes v1 packet', () {
    final pkt = Uint8List(52);
    pkt[0] = 0x4F; // O
    pkt[1] = 0x44; // D
    pkt[2] = 0x47; // G
    pkt[3] = 0x50; // P
    pkt[4] = 1;
    pkt[5] = 3; // 3D
    pkt[6] = 0x01; // gnssFixOK
    pkt[7] = 14;
    final bd = ByteData.sublistView(pkt);
    bd.setUint32(8, 123456, Endian.little);
    bd.setInt32(12, 170123456, Endian.little); // lon
    bd.setInt32(16, 492345678, Endian.little); // lat
    bd.setInt32(20, 280000, Endian.little); // 280 m
    bd.setInt32(24, 27778, Endian.little); // ~100 km/h
    bd.setInt32(28, 9000000, Endian.little); // 90°
    bd.setUint32(32, 2500, Endian.little); // 2.5 m
    bd.setUint32(36, 4000, Endian.little);
    bd.setUint32(40, 200, Endian.little);
    bd.setUint16(44, 2026, Endian.little);
    pkt[46] = 7;
    pkt[47] = 26;
    pkt[48] = 12;
    pkt[49] = 0;
    pkt[50] = 1;

    final fix = OdgpParser.tryParse(pkt);
    expect(fix, isNotNull);
    expect(fix!.valid, isTrue);
    expect(fix.numSV, 14);
    expect(fix.hAccM, closeTo(2.5, 0.001));
    expect(fix.speedKmh, closeTo(100.0, 0.1));
    expect(fix.latitude, closeTo(49.2345678, 1e-6));
  });
}

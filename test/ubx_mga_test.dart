import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/ubx_mga.dart';

void main() {
  group('UbxMga', () {
    test('TIME_UTC frame has sync, class/id and valid checksum', () {
      final msg = UbxMga.timeUtc(DateTime.utc(2026, 7, 25, 12, 34, 56));
      expect(msg[0], 0xB5);
      expect(msg[1], 0x62);
      expect(msg[2], 0x13);
      expect(msg[3], 0x40);
      expect(msg[4], 24); // payload length LE
      expect(msg[5], 0);
      expect(msg[6], 0x10); // type TIME_UTC
      expect(msg.length, 8 + 24);
      expect(_checksumOk(msg), isTrue);
    });

    test('POS_LLH encodes lat/lon scale 1e-7', () {
      final msg = UbxMga.posLlh(
        latitudeDeg: 50.0755,
        longitudeDeg: 14.4378,
        altitudeMeters: 200,
        posAccMeters: 5000,
      );
      expect(msg[6], 0x01); // type POS_LLH
      expect(msg.length, 8 + 20);
      expect(_checksumOk(msg), isTrue);

      // lat at payload offset 4 → absolute offset 10
      final lat = _readI32Le(msg, 10);
      expect(lat, 500755000);
      final lon = _readI32Le(msg, 14);
      expect(lon, 144378000);
    });

    test('accuracy grows with age', () {
      expect(
        UbxMga.accuracyMetersForAge(const Duration(hours: 1)),
        lessThan(UbxMga.accuracyMetersForAge(const Duration(days: 10))),
      );
    });
  });
}

bool _checksumOk(List<int> packet) {
  var ckA = 0;
  var ckB = 0;
  for (var i = 2; i < packet.length - 2; i++) {
    ckA = (ckA + packet[i]) & 0xff;
    ckB = (ckB + ckA) & 0xff;
  }
  return packet[packet.length - 2] == ckA && packet[packet.length - 1] == ckB;
}

int _readI32Le(List<int> b, int offset) {
  return b[offset] |
      (b[offset + 1] << 8) |
      (b[offset + 2] << 16) |
      (b[offset + 3] << 24);
}

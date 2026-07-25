import 'dart:convert';
import 'dart:typed_data';

/// u-blox config helpers to enable GSV/GSA for sky view.
class UbxCfg {
  UbxCfg._();

  static const int _classCfg = 0x06;
  static const int _idValset = 0x8A;
  static const int _idMsg = 0x01;

  static const int keyUart1InUbx = 0x10740001;
  static const int keyNmeaGsvUart1 = 0x209100c5;
  static const int keyNmeaGsaUart1 = 0x209100c0;

  static const int nmeaClass = 0xF0;
  static const int nmeaGsvId = 0x04;
  static const int nmeaGsaId = 0x02;

  static List<Uint8List> pubxDetailFrames({required bool enable}) {
    final rate = enable ? 1 : 0;
    return [
      Uint8List.fromList(utf8.encode(pubxSetMsgRate('GSV', rate))),
      Uint8List.fromList(utf8.encode(pubxSetMsgRate('GSA', rate))),
      // Some firmwares use these aliases.
      Uint8List.fromList(utf8.encode(pubxSetMsgRate('GSV', rate, allPorts: true))),
    ];
  }

  static List<Uint8List> ubxDetailFrames({required bool enable}) {
    final valRate = enable ? 5 : 0; // every 5th epoch @ 10 Hz ≈ 2 Hz
    final portRate = enable ? 1 : 0;
    return [
      valSetL(keyUart1InUbx, true),
      valSetU1(keyNmeaGsvUart1, valRate),
      valSetU1(keyNmeaGsaUart1, valRate),
      cfgMsg(nmeaClass, nmeaGsvId, rateUart1: portRate),
      cfgMsg(nmeaClass, nmeaGsaId, rateUart1: portRate),
    ];
  }

  /// `$PUBX,40,<msg>,rDDC,rUART1,rUART2,rUSB,rSPI,0*CS\r\n`
  static String pubxSetMsgRate(
    String msgId,
    int uart1Rate, {
    bool allPorts = false,
  }) {
    final r = uart1Rate.clamp(0, 255);
    final body = allPorts
        ? 'PUBX,40,$msgId,$r,$r,$r,$r,$r,0'
        : 'PUBX,40,$msgId,0,$r,0,0,0,0';
    var cs = 0;
    for (final cu in body.codeUnits) {
      cs ^= cu;
    }
    final hex = cs.toRadixString(16).toUpperCase().padLeft(2, '0');
    return '\$$body*$hex\r\n';
  }

  static Uint8List valSetU1(int keyId, int value, {int layers = 0x01}) {
    final payload = ByteData(9);
    payload.setUint8(0, 0x00);
    payload.setUint8(1, layers);
    payload.setUint8(2, 0);
    payload.setUint8(3, 0);
    payload.setUint32(4, keyId, Endian.little);
    payload.setUint8(8, value & 0xff);
    return _frame(_classCfg, _idValset, payload.buffer.asUint8List());
  }

  static Uint8List valSetL(int keyId, bool value, {int layers = 0x01}) {
    return valSetU1(keyId, value ? 1 : 0, layers: layers);
  }

  static Uint8List cfgMsg(
    int msgClass,
    int msgId, {
    int rateI2c = 0,
    int rateUart1 = 0,
    int rateUart2 = 0,
    int rateUsb = 0,
    int rateSpi = 0,
  }) {
    final payload = Uint8List.fromList([
      msgClass & 0xff,
      msgId & 0xff,
      rateI2c & 0xff,
      rateUart1 & 0xff,
      rateUart2 & 0xff,
      rateUsb & 0xff,
      rateSpi & 0xff,
      0x00,
    ]);
    return _frame(_classCfg, _idMsg, payload);
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
    for (var i = 2; i < 6 + len; i++) {
      ckA = (ckA + packet[i]) & 0xff;
      ckB = (ckB + ckA) & 0xff;
    }
    packet[6 + len] = ckA;
    packet[7 + len] = ckB;
    return packet;
  }
}

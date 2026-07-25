import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/utils/nmea_parser.dart';

String withChecksum(String sentenceWithoutStar) {
  int calculatedChecksum = 0;
  for (int i = 1; i < sentenceWithoutStar.length; i++) {
    calculatedChecksum ^= sentenceWithoutStar.codeUnitAt(i);
  }
  final hex = calculatedChecksum.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '$sentenceWithoutStar*$hex';
}

void main() {
  group('NmeaParser Tests', () {
    test('parses GPS and GNSS RMC sentences (speed)', () {
      final gpRmc = NmeaParser.parse(withChecksum('\$GPRMC,123519,A,4807.038,N,01131.000,E,22.4,084.4,230394,003.1,W'));
      expect(gpRmc, isNotNull);
      expect(gpRmc!.speedKmh, closeTo(22.4 * 1.852, 0.001));
      expect(gpRmc.latitude, closeTo(48.1173, 0.0001));
      expect(gpRmc.longitude, closeTo(11.516667, 0.0001));
      expect(gpRmc.timeSeconds, closeTo(45319.0, 0.001));

      final gnRmc = NmeaParser.parse(withChecksum('\$GNRMC,123519,A,4807.038,N,01131.000,E,22.4,084.4,230394,003.1,W'));
      expect(gnRmc, isNotNull);
      expect(gnRmc!.speedKmh, closeTo(22.4 * 1.852, 0.001));
      expect(gnRmc.latitude, closeTo(48.1173, 0.0001));
      expect(gnRmc.longitude, closeTo(11.516667, 0.0001));
      expect(gnRmc.timeSeconds, closeTo(45319.0, 0.001));
    });

    test('parses GLONASS, Galileo, and BeiDou RMC sentences (speed)', () {
      // GLONASS
      final glRmc = NmeaParser.parse(withChecksum('\$GLRMC,123519,A,4807.038,N,01131.000,E,15.5,084.4,230394,003.1,W'));
      expect(glRmc, isNotNull);
      expect(glRmc!.speedKmh, closeTo(15.5 * 1.852, 0.001));

      // Galileo
      final gaRmc = NmeaParser.parse(withChecksum('\$GARMC,123519,A,4807.038,N,01131.000,E,10.0,084.4,230394,003.1,W'));
      expect(gaRmc, isNotNull);
      expect(gaRmc!.speedKmh, closeTo(10.0 * 1.852, 0.001));

      // BeiDou
      final gbRmc = NmeaParser.parse(withChecksum('\$GBRMC,123519,A,4807.038,N,01131.000,E,35.2,084.4,230394,003.1,W'));
      expect(gbRmc, isNotNull);
      expect(gbRmc!.speedKmh, closeTo(35.2 * 1.852, 0.001));
    });

    test('parses GGA sentences (satellites, hdop and altitude)', () {
      final gnGga = NmeaParser.parse(withChecksum('\$GNGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,'));
      expect(gnGga, isNotNull);
      expect(gnGga!.satellites, 8);
      expect(gnGga.hdop, 0.9);
      expect(gnGga.altitude, 545.4);
      expect(gnGga.latitude, closeTo(48.1173, 0.0001));
      expect(gnGga.longitude, closeTo(11.516667, 0.0001));

      final glGga = NmeaParser.parse(withChecksum('\$GLGGA,123519,4807.038,N,01131.000,E,1,12,1.2,545.4,M,46.9,M,,'));
      expect(glGga, isNotNull);
      expect(glGga!.satellites, 12);
      expect(glGga.hdop, 1.2);
      expect(glGga.altitude, 545.4);
      expect(glGga.latitude, closeTo(48.1173, 0.0001));
      expect(glGga.longitude, closeTo(11.516667, 0.0001));
    });

    test('parses GSA sentences (DOP + used PRNs, ignores satellite count)', () {
      final gnGsa = NmeaParser.parse(withChecksum('\$GNGSA,A,3,04,05,,09,12,,,24,,,,,2.5,1.3,2.1'));
      expect(gnGsa, isNotNull);
      expect(gnGsa!.satellites, isNull);
      expect(gnGsa.hdop, 1.3);
      expect(gnGsa.pdop, 2.5);
      expect(gnGsa.vdop, 2.1);
      expect(gnGsa.usedPrns, {4, 5, 9, 12, 24});

      final glGsa = NmeaParser.parse(withChecksum('\$GLGSA,A,3,04,05,,09,12,,,24,,,,,2.5,1.3,2.1'));
      expect(glGsa, isNotNull);
      expect(glGsa!.satellites, isNull);
      expect(glGsa.hdop, 1.3);
    });

    test('parses GSV satellite sky fragments', () {
      final gsv = NmeaParser.parse(
        withChecksum(
          '\$GPGSV,2,1,07,07,79,048,42,02,61,018,43,26,49,275,44,27,45,138,42',
        ),
      );
      expect(gsv, isNotNull);
      expect(gsv!.gsv, isNotNull);
      expect(gsv.gsv!.talker, 'GP');
      expect(gsv.gsv!.totalMessages, 2);
      expect(gsv.gsv!.messageNumber, 1);
      expect(gsv.gsv!.satsInView, 7);
      expect(gsv.gsv!.satellites.length, 4);
      expect(gsv.gsv!.satellites.first.prn, 7);
      expect(gsv.gsv!.satellites.first.elevationDeg, 79);
      expect(gsv.gsv!.satellites.first.snrDbHz, 42);
    });

    test('rejects NMEA sentences with invalid checksums', () {
      final badRmc = NmeaParser.parse('\$GPRMC,123519,A,4807.038,N,01131.000,E,22.4,084.4,230394,003.1,W*99');
      expect(badRmc, isNull);
    });
  });
}

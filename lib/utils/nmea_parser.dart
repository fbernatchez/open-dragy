import '../models/satellite_sv.dart';

class NmeaData {
  final double? speedKmh;
  final int? satellites;
  final double? hdop;
  final double? pdop;
  final double? vdop;
  final double? altitude;
  final double? latitude;
  final double? longitude;
  final double? timeSeconds;
  final int? fixQuality;
  final int? fixMode; // GSA: 1=none, 2=2D, 3=3D
  final Set<int>? usedPrns;
  final NmeaGsvFragment? gsv;

  NmeaData({
    this.speedKmh,
    this.satellites,
    this.hdop,
    this.pdop,
    this.vdop,
    this.altitude,
    this.latitude,
    this.longitude,
    this.timeSeconds,
    this.fixQuality,
    this.fixMode,
    this.usedPrns,
    this.gsv,
  });
}

class NmeaGsvFragment {
  final String talker;
  final int totalMessages;
  final int messageNumber;
  final int satsInView;
  final List<SatelliteSv> satellites;

  const NmeaGsvFragment({
    required this.talker,
    required this.totalMessages,
    required this.messageNumber,
    required this.satsInView,
    required this.satellites,
  });
}

class NmeaParser {
  /// Returns true if the sentence starts with $ followed by a 2-character talker ID and the specified sentence type.
  static bool _matches(String sentence, String type) {
    if (sentence.length < 6 || !sentence.startsWith('\$')) return false;
    return sentence.substring(3, 6) == type;
  }

  static String? _talker(String sentence) {
    if (sentence.length < 3 || !sentence.startsWith('\$')) return null;
    return sentence.substring(1, 3);
  }

  /// Validates the NMEA checksum.
  static bool _isValidChecksum(String sentence) {
    if (!sentence.startsWith('\$')) return false;
    final starIndex = sentence.indexOf('*');
    if (starIndex == -1 || starIndex + 3 > sentence.length) return false;

    final dataToCalculate = sentence.substring(1, starIndex);
    final checksumStr = sentence.substring(starIndex + 1, starIndex + 3);

    int calculatedChecksum = 0;
    for (int i = 0; i < dataToCalculate.length; i++) {
      calculatedChecksum ^= dataToCalculate.codeUnitAt(i);
    }

    final calculatedChecksumStr =
        calculatedChecksum.toRadixString(16).toUpperCase().padLeft(2, '0');
    return checksumStr.toUpperCase() == calculatedChecksumStr;
  }

  static String _field(String raw) {
    final star = raw.indexOf('*');
    return star == -1 ? raw : raw.substring(0, star);
  }

  static double? _parseLatitude(String val, String hemi) {
    if (val.length < 2 || hemi.isEmpty) return null;
    try {
      final degrees = double.parse(val.substring(0, 2));
      final minutes = double.parse(val.substring(2));
      double decimal = degrees + (minutes / 60.0);
      if (hemi == 'S') decimal = -decimal;
      return decimal;
    } catch (_) {
      return null;
    }
  }

  static double? _parseLongitude(String val, String hemi) {
    if (val.length < 3 || hemi.isEmpty) return null;
    try {
      final degrees = double.parse(val.substring(0, 3));
      final minutes = double.parse(val.substring(3));
      double decimal = degrees + (minutes / 60.0);
      if (hemi == 'W') decimal = -decimal;
      return decimal;
    } catch (_) {
      return null;
    }
  }

  static double? _parseUtcTime(String val) {
    if (val.length < 6) return null;
    try {
      final hh = double.parse(val.substring(0, 2));
      final mm = double.parse(val.substring(2, 4));
      final ss = double.parse(val.substring(4));
      return hh * 3600.0 + mm * 60.0 + ss;
    } catch (_) {
      return null;
    }
  }

  /// Parses NMEA sentence and returns NmeaData.
  /// Handles both $GP and $GN talker prefixes.
  static NmeaData? parse(String sentence) {
    if (!_isValidChecksum(sentence)) return null;
    // --- Speed: RMC (Recommended Minimum Specific GPS Data) ---
    if (_matches(sentence, 'RMC')) {
      final parts = sentence.split(',');
      if (parts.length < 8) return null;

      final status = parts[2];
      if (status != 'A') {
        // 'A' = active fix, 'V' = void (no fix)
        return null;
      }

      final speedKnotsStr = parts[7];
      if (speedKnotsStr.isEmpty) return null;

      double? speedKmh;
      try {
        final speedKnots = double.parse(speedKnotsStr);
        speedKmh = speedKnots * 1.852;
      } catch (_) {
        return null;
      }

      double? lat;
      double? lon;
      if (parts.length >= 7) {
        lat = _parseLatitude(parts[3], parts[4]);
        lon = _parseLongitude(parts[5], parts[6]);
      }

      final timeStr = parts[1];
      final timeSec = _parseUtcTime(timeStr);

      return NmeaData(
        speedKmh: speedKmh,
        latitude: lat,
        longitude: lon,
        timeSeconds: timeSec,
      );
    }

    // --- Satellites + HDOP: GGA (Global Positioning System Fix Data) ---
    if (_matches(sentence, 'GGA')) {
      final parts = sentence.split(',');
      if (parts.length < 10) return null;

      // parts[6]: fix quality (0 = no fix)
      final fixQuality = int.tryParse(parts[6]) ?? 0;
      if (fixQuality == 0) return null;

      int? satellites;
      double? hdop;
      double? altitude;
      double? lat;
      double? lon;

      try {
        if (parts[7].isNotEmpty) satellites = int.parse(parts[7]);
        final hdopStr = _field(parts[8]);
        if (hdopStr.isNotEmpty) hdop = double.parse(hdopStr);
        if (parts.length > 9 && parts[9].isNotEmpty) {
          altitude = double.tryParse(_field(parts[9]));
        }
        lat = _parseLatitude(parts[2], parts[3]);
        lon = _parseLongitude(parts[4], parts[5]);
      } catch (_) {
        return null;
      }

      if (satellites != null ||
          hdop != null ||
          altitude != null ||
          lat != null ||
          lon != null) {
        return NmeaData(
          satellites: satellites,
          hdop: hdop,
          altitude: altitude,
          latitude: lat,
          longitude: lon,
          fixQuality: fixQuality,
        );
      }
    }

    // --- Active SVs + DOP: GSA ---
    // $GNGSA,A,3,04,05,...,1.5,1.0,1.2*05
    if (_matches(sentence, 'GSA')) {
      final parts = sentence.split(',');
      if (parts.length < 18) return null;

      final mode = int.tryParse(parts[2]) ?? 1;
      final used = <int>{};
      for (var i = 3; i <= 14; i++) {
        final id = int.tryParse(parts[i]);
        if (id != null && id > 0) used.add(id);
      }

      double? pdop;
      double? hdop;
      double? vdop;
      try {
        final pdopStr = _field(parts[15]);
        final hdopStr = _field(parts[16]);
        final vdopStr = _field(parts[17]);
        if (pdopStr.isNotEmpty) pdop = double.tryParse(pdopStr);
        if (hdopStr.isNotEmpty) hdop = double.tryParse(hdopStr);
        if (vdopStr.isNotEmpty) vdop = double.tryParse(vdopStr);
      } catch (_) {}

      return NmeaData(
        fixMode: mode,
        usedPrns: used.isEmpty ? null : used,
        pdop: pdop,
        hdop: hdop,
        vdop: vdop,
      );
    }

    // --- Sky view: GSV ---
    // $GPGSV,3,1,12,01,40,083,41,02,17,308,45,12,07,297,42,14,22,157,41*78
    if (_matches(sentence, 'GSV')) {
      final parts = sentence.split(',');
      if (parts.length < 4) return null;
      final talker = _talker(sentence) ?? 'GN';
      final total = int.tryParse(parts[1]) ?? 0;
      final msgNum = int.tryParse(parts[2]) ?? 0;
      final inView = int.tryParse(_field(parts[3])) ?? 0;
      if (total <= 0 || msgNum <= 0) return null;

      final sats = <SatelliteSv>[];
      // Up to 4 satellite blocks: prn, elev, az, snr
      var i = 4;
      while (i + 3 < parts.length) {
        final prnStr = parts[i];
        if (prnStr.isEmpty) break;
        final prn = int.tryParse(prnStr);
        final elev = int.tryParse(parts[i + 1]);
        final az = int.tryParse(parts[i + 2]);
        final snrRaw = _field(parts[i + 3]);
        final snr = snrRaw.isEmpty ? null : int.tryParse(snrRaw);
        if (prn != null && elev != null && az != null) {
          sats.add(
            SatelliteSv(
              talker: talker,
              prn: prn,
              elevationDeg: elev.clamp(0, 90),
              azimuthDeg: az % 360,
              snrDbHz: snr,
            ),
          );
        }
        i += 4;
      }

      return NmeaData(
        gsv: NmeaGsvFragment(
          talker: talker,
          totalMessages: total,
          messageNumber: msgNum,
          satsInView: inView,
          satellites: sats,
        ),
      );
    }

    return null;
  }

  static String fixQualityLabel(int? q) {
    switch (q) {
      case 1:
        return 'GPS';
      case 2:
        return 'DGPS';
      case 3:
        return 'PPS';
      case 4:
        return 'RTK fixed';
      case 5:
        return 'RTK float';
      case 6:
        return 'Estimated';
      default:
        return q == null ? '—' : 'Fix $q';
    }
  }
}

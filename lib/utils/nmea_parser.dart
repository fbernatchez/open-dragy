class NmeaData {
  final double? speedKmh;
  final int? satellites;
  final double? hdop;
  final double? altitude;
  final double? latitude;
  final double? longitude;

  NmeaData({
    this.speedKmh,
    this.satellites,
    this.hdop,
    this.altitude,
    this.latitude,
    this.longitude,
  });
}

class NmeaParser {
  /// Returns true if the sentence starts with $ followed by a 2-character talker ID and the specified sentence type.
  static bool _matches(String sentence, String type) {
    if (sentence.length < 6 || !sentence.startsWith('\$')) return false;
    return sentence.substring(3, 6) == type;
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

      return NmeaData(speedKmh: speedKmh, latitude: lat, longitude: lon);
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
        // parts[8] may end with checksum e.g. "0.9*47" — strip it
        final hdopStr = parts[8].contains('*') ? parts[8].split('*')[0] : parts[8];
        if (hdopStr.isNotEmpty) hdop = double.parse(hdopStr);
        if (parts.length > 9 && parts[9].isNotEmpty) {
          final altitudeStr = parts[9].contains('*') ? parts[9].split('*')[0] : parts[9];
          altitude = double.tryParse(altitudeStr);
        }
        lat = _parseLatitude(parts[2], parts[3]);
        lon = _parseLongitude(parts[4], parts[5]);
      } catch (_) {
        return null;
      }

      if (satellites != null || hdop != null || altitude != null || lat != null || lon != null) {
        return NmeaData(
          satellites: satellites,
          hdop: hdop,
          altitude: altitude,
          latitude: lat,
          longitude: lon,
        );
      }
    }

    // --- Satellites (fallback): GSA (GNSS DOP and Active Satellites) ---
    // $GNGSA,A,3,04,05,...,1.5,1.0,1.2*05
    // parts[2] = mode (1=no fix, 2=2D, 3=3D) — use as sanity check
    if (_matches(sentence, 'GSA')) {
      final parts = sentence.split(',');
      if (parts.length < 18) return null;

      final mode = int.tryParse(parts[2]) ?? 1;
      if (mode < 2) return null; // No fix

      // HDOP is parts[16], strip checksum
      double? hdop;
      try {
        final hdopStr = parts[16].contains('*') ? parts[16].split('*')[0] : parts[16];
        if (hdopStr.isNotEmpty) hdop = double.parse(hdopStr);
      } catch (_) {}

      if (hdop != null) {
        return NmeaData(hdop: hdop);
      }
    }

    return null;
  }
}

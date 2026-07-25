/// One GNSS satellite from NMEA GSV.
class SatelliteSv {
  final String talker; // GP, GL, GA, GB, GQ, …
  final int prn;
  final int elevationDeg; // 0–90
  final int azimuthDeg; // 0–359
  final int? snrDbHz; // null / 0 = not tracking

  const SatelliteSv({
    required this.talker,
    required this.prn,
    required this.elevationDeg,
    required this.azimuthDeg,
    this.snrDbHz,
  });

  bool get isTracking => (snrDbHz ?? 0) > 0;

  String get constellationLabel {
    switch (talker.toUpperCase()) {
      case 'GP':
        return 'GPS';
      case 'GL':
        return 'GLONASS';
      case 'GA':
        return 'Galileo';
      case 'GB':
      case 'BD':
        return 'BeiDou';
      case 'GQ':
      case 'QZ':
        return 'QZSS';
      case 'GI':
        return 'NavIC';
      case 'GN':
        return 'GNSS';
      default:
        return talker;
    }
  }

  String get idLabel => '$talker$prn';
}

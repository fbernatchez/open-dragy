import '../utils/odgp_parser.dart';

/// NAV-PVT / ODGP fields for raw logging and future physics replay.
class GpsPvtSample {
  final double speedKmh;
  final double? latitude;
  final double? longitude;
  final double? altitudeM;
  final int? iTowMs;
  final int? fixType;
  final int? satellites;
  final double? hAccM;
  final double? vAccM;
  final double? sAccMps;
  final double? headingDeg;
  final double? hdop;
  final bool usedPvt;

  const GpsPvtSample({
    required this.speedKmh,
    this.latitude,
    this.longitude,
    this.altitudeM,
    this.iTowMs,
    this.fixType,
    this.satellites,
    this.hAccM,
    this.vAccM,
    this.sAccMps,
    this.headingDeg,
    this.hdop,
    this.usedPvt = true,
  });

  factory GpsPvtSample.fromOdgp(OdgpFix fix, {double? hdopApprox}) {
    return GpsPvtSample(
      speedKmh: fix.speedKmh,
      latitude: fix.valid ? fix.latitude : null,
      longitude: fix.valid ? fix.longitude : null,
      altitudeM: fix.altitudeM,
      iTowMs: fix.iTOW,
      fixType: fix.fixType,
      satellites: fix.numSV,
      hAccM: fix.hAccM > 0 ? fix.hAccM : null,
      vAccM: fix.vAccM > 0 ? fix.vAccM : null,
      sAccMps: fix.sAccMps > 0 ? fix.sAccMps : null,
      headingDeg: fix.headingDeg,
      hdop: hdopApprox,
      usedPvt: true,
    );
  }
}

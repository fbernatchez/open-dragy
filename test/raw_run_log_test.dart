import 'package:flutter_test/flutter_test.dart';
import 'package:open_dragy/models/gps_pvt_sample.dart';
import 'package:open_dragy/models/raw_run_log.dart';
import 'package:open_dragy/utils/odgp_parser.dart';

void main() {
  test('RawGpsSample round-trips NAV-PVT JSON fields', () {
    final sample = RawGpsSample.fromPvt(
      elapsedMs: 100,
      timeUtc: '2026-07-27T03:41:40.287983Z',
      pvt: const GpsPvtSample(
        valid: false,
        speedKmh: 54.3,
        latitude: 49.26,
        longitude: 16.97,
        altitudeM: 273.5,
        iTowMs: 123456789,
        fixType: 3,
        satellites: 20,
        hAccM: 0.28,
        vAccM: 0.35,
        sAccMps: 0.08,
        headingDeg: 90.0,
        hdop: 0.1,
        usedPvt: true,
      ),
    );

    final restored = RawGpsSample.fromJson(sample.toJson());
    expect(restored.valid, isFalse);
    expect(restored.iTowMs, 123456789);
    expect(restored.hAccM, 0.28);
    expect(restored.vAccM, 0.35);
    expect(restored.sAccMps, 0.08);
    expect(restored.usedPvt, isTrue);
    expect(restored.fixType, 3);
    expect(restored.latitude, 49.26);
  });

  test('RunRawCapture GPS CSV includes NAV-PVT header and values', () {
    final capture = RunRawCapture()..startArmed();
    capture.addGpsPvt(
      const GpsPvtSample(
        speedKmh: 10.0,
        iTowMs: 999000,
        hAccM: 0.4,
        fixType: 3,
        satellites: 18,
        usedPvt: true,
      ),
    );

    final csv = capture.toGpsCsv();
    expect(csv.startsWith(RunRawCapture.gpsCsvHeader), isTrue);
    expect(csv, contains('999000'));
    expect(csv, contains('0.400'));
    expect(csv, contains(',1\n'));
  });

  test('GpsPvtSample.fromOdgp maps ODGP fix fields', () {
    final fix = OdgpFix(
      version: 1,
      fixType: 3,
      flags: 3,
      numSV: 14,
      iTOW: 555000,
      latitude: 49.0,
      longitude: 16.0,
      altitudeM: 280.0,
      speedKmh: 72.0,
      headingDeg: 45.0,
      hAccM: 0.25,
      vAccM: 0.4,
      sAccMps: 0.07,
      year: 2026,
      month: 7,
      day: 27,
      hour: 5,
      minute: 41,
      second: 53,
    );

    final pvt = GpsPvtSample.fromOdgp(fix, hdopApprox: 0.1);
    expect(pvt.valid, isTrue);
    expect(pvt.iTowMs, 555000);
    expect(pvt.hAccM, 0.25);
    expect(pvt.usedPvt, isTrue);
  });
}

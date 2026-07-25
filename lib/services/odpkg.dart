import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'ride_recorder.dart';

/// Packs a logger session into a single `.odpkg` ZIP for PC transfer.
///
/// Inner layout (stable names — analyzer expects these):
/// ```
/// manifest.json
/// track.gpx
/// gps.csv
/// imu.csv
/// ```
class OdPkg {
  OdPkg._();

  static Future<File?> packSession(String sessionId) async {
    final dir = await RideRecorder.ridesDirectory();
    final manifestFile = File(p.join(dir.path, '$sessionId.odlog.json'));
    if (!await manifestFile.exists()) return null;

    Map<String, dynamic> manifest;
    try {
      manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final filesMap = manifest['files'] as Map<String, dynamic>?;
    final gpxName = filesMap?['gpx'] as String? ?? '$sessionId.gpx';
    final gpsName = filesMap?['gps_csv'] as String? ?? '${sessionId}_gps.csv';
    final imuName = filesMap?['imu_csv'] as String? ?? '${sessionId}_imu.csv';

    final gpx = File(p.join(dir.path, gpxName));
    final gps = File(p.join(dir.path, gpsName));
    final imu = File(p.join(dir.path, imuName));
    if (!await gpx.exists() || !await gps.exists() || !await imu.exists()) {
      return null;
    }

    final archive = Archive();
    archive.addFile(
      ArchiveFile(
        'manifest.json',
        manifestFile.lengthSync(),
        await manifestFile.readAsBytes(),
      ),
    );
    archive.addFile(
      ArchiveFile('track.gpx', gpx.lengthSync(), await gpx.readAsBytes()),
    );
    archive.addFile(
      ArchiveFile('gps.csv', gps.lengthSync(), await gps.readAsBytes()),
    );
    archive.addFile(
      ArchiveFile('imu.csv', imu.lengthSync(), await imu.readAsBytes()),
    );

    final bytes = ZipEncoder().encode(archive);
    final out = File(p.join(dir.path, '$sessionId.odpkg'));
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }
}

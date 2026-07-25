import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Session recorder for Logger mode (GPX + CSV + manifest for PC analysis).
class RideRecorder {
  IOSink? _sink;
  File? _gpxFile;
  File? _imuCsvFile;
  File? _gpsCsvFile;
  String? _sessionId;
  String? _projectTag;
  String? _configuration;
  int _trackPointCount = 0;
  int _gpsRowCount = 0;
  DateTime? _startedAt;

  File? get gpxFile => _gpxFile;
  String? get sessionId => _sessionId;
  int get trackPointCount => _trackPointCount;
  int get gpsRowCount => _gpsRowCount;
  DateTime? get startedAt => _startedAt;
  bool get isRecording => _sink != null;

  static Future<Directory> ridesDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/rides');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<List<File>> listSessionManifests() async {
    final dir = await ridesDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.odlog.json'))
        .toList();
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return files;
  }

  static Future<List<File>> listGpxFiles() async {
    final dir = await ridesDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gpx'))
        .toList();
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return files;
  }

  static String? sessionIdFromRideFile(File file) {
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path.split(Platform.pathSeparator).last;
    if (name.endsWith('.odlog.json')) {
      return name.substring(0, name.length - '.odlog.json'.length);
    }
    if (name.endsWith('.gpx')) {
      return name.substring(0, name.length - '.gpx'.length);
    }
    if (name.endsWith('_gps.csv')) {
      return name.substring(0, name.length - '_gps.csv'.length);
    }
    if (name.endsWith('_imu.csv')) {
      return name.substring(0, name.length - '_imu.csv'.length);
    }
    return null;
  }

  Future<void> start({
    String? vehicleName,
    String? projectTag,
    String? configuration,
  }) async {
    if (_sink != null) return;

    final dir = await ridesDirectory();
    _startedAt = DateTime.now();
    final stamp =
        '${_startedAt!.year}${_pad(_startedAt!.month)}${_pad(_startedAt!.day)}_'
        '${_pad(_startedAt!.hour)}${_pad(_startedAt!.minute)}${_pad(_startedAt!.second)}';
    _sessionId = 'ride_$stamp';
    _projectTag = projectTag;
    _configuration = configuration?.trim().isEmpty == true
        ? null
        : configuration?.trim();
    _gpxFile = File('${dir.path}/$_sessionId.gpx');
    _imuCsvFile = File('${dir.path}/${_sessionId}_imu.csv');
    _gpsCsvFile = File('${dir.path}/${_sessionId}_gps.csv');

    _sink = _gpxFile!.openWrite(mode: FileMode.writeOnly);
    _trackPointCount = 0;
    _gpsRowCount = 0;

    final name = vehicleName ?? 'OpenDragy logger';
    _sink!.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    _sink!.writeln(
      '<gpx version="1.1" creator="OpenDragy Logger" '
      'xmlns="http://www.topografix.com/GPX/1/1">',
    );
    _sink!.writeln('  <metadata>');
    _sink!.writeln(
      '    <time>${_formatUtc(_startedAt!.toUtc())}</time>',
    );
    final desc = _configuration != null
        ? '$name — ${_configuration!}'
        : name;
    _sink!.writeln('    <desc>${_escapeXml(desc)}</desc>');
    if (projectTag != null && projectTag.isNotEmpty) {
      _sink!.writeln(
        '    <keywords>${_escapeXml('project:$projectTag')}</keywords>',
      );
    }
    _sink!.writeln('  </metadata>');
    _sink!.writeln('  <trk>');
    _sink!.writeln('    <name>${_escapeXml(name)}</name>');
    _sink!.writeln('    <trkseg>');

    await _imuCsvFile!.writeAsString(
      'elapsed_ms,ax_g,ay_g,az_g\n',
      mode: FileMode.writeOnly,
    );
    await _gpsCsvFile!.writeAsString(
      'elapsed_ms,time_utc,lat,lon,speed_kmh,hacc_m,fix_type,heading_deg,hdop,sats,alt_m\n',
      mode: FileMode.writeOnly,
    );
    await _sink!.flush();
  }

  Future<void> appendTrackPoint({
    required double latitude,
    required double longitude,
    double? altitudeMeters,
    double? speedKmh,
    DateTime? timeUtc,
  }) async {
    if (_sink == null) return;

    final t = timeUtc ?? DateTime.now().toUtc();
    _sink!.writeln(
      '      <trkpt lat="$latitude" lon="$longitude">',
    );
    if (altitudeMeters != null) {
      _sink!.writeln('        <ele>$altitudeMeters</ele>');
    }
    _sink!.writeln('        <time>${_formatUtc(t)}</time>');
    if (speedKmh != null) {
      final speedMs = speedKmh / 3.6;
      _sink!.writeln(
        '        <extensions>'
        '<speed_ms>${speedMs.toStringAsFixed(3)}</speed_ms>'
        '</extensions>',
      );
    }
    _sink!.writeln('      </trkpt>');
    _trackPointCount++;

    if (_trackPointCount % 10 == 0) {
      await _sink!.flush();
    }
  }

  Future<void> appendGpsRow({
    required double latitude,
    required double longitude,
    double? altitudeMeters,
    double? speedKmh,
    double? hAccMeters,
    int? fixType,
    double? headingDeg,
    double? hdop,
    int? satellites,
    DateTime? timeUtc,
  }) async {
    if (_gpsCsvFile == null || !isRecording || _startedAt == null) return;
    final t = timeUtc ?? DateTime.now().toUtc();
    final elapsedMs = t.difference(_startedAt!.toUtc()).inMilliseconds;
    final alt = altitudeMeters?.toStringAsFixed(2) ?? '';
    final spd = speedKmh?.toStringAsFixed(3) ?? '';
    final hacc = hAccMeters?.toStringAsFixed(3) ?? '';
    final fix = fixType?.toString() ?? '';
    final hdg = headingDeg?.toStringAsFixed(2) ?? '';
    final hd = hdop?.toStringAsFixed(2) ?? '';
    final sats = satellites?.toString() ?? '';
    await _gpsCsvFile!.writeAsString(
      '$elapsedMs,${_formatUtc(t)},$latitude,$longitude,$spd,$hacc,$fix,$hdg,$hd,$sats,$alt\n',
      mode: FileMode.append,
    );
    _gpsRowCount++;
  }

  Future<void> appendImuSample({
    required int elapsedMs,
    required double axG,
    required double ayG,
    required double azG,
  }) async {
    if (_imuCsvFile == null || !isRecording) return;
    await _imuCsvFile!.writeAsString(
      '$elapsedMs,${axG.toStringAsFixed(5)},${ayG.toStringAsFixed(5)},${azG.toStringAsFixed(5)}\n',
      mode: FileMode.append,
    );
  }

  Future<File?> stop({String? vehicleName}) async {
    if (_sink == null) return _gpxFile;

    _sink!.writeln('    </trkseg>');
    _sink!.writeln('  </trk>');
    _sink!.writeln('</gpx>');
    await _sink!.flush();
    await _sink!.close();
    _sink = null;

    final endedAt = DateTime.now().toUtc();
    final sessionId = _sessionId;
    if (sessionId != null) {
      final manifestFile = File(
        '${(await ridesDirectory()).path}/$sessionId.odlog.json',
      );
      final manifest = {
        'format': 'open-dragy-logger',
        'version': 2,
        'gpsCsvColumns':
            'elapsed_ms,time_utc,lat,lon,speed_kmh,hacc_m,fix_type,heading_deg,hdop,sats,alt_m',
        'sessionId': sessionId,
        'startedAt': _startedAt?.toUtc().toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'project': _projectTag,
        'configuration': _configuration,
        'vehicle': vehicleName,
        'trackPoints': _trackPointCount,
        'gpsRows': _gpsRowCount,
        'files': {
          'gpx': '$sessionId.gpx',
          'gps_csv': '${sessionId}_gps.csv',
          'imu_csv': '${sessionId}_imu.csv',
        },
      };
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
    }

    final file = _gpxFile;
    _gpxFile = null;
    _imuCsvFile = null;
    _gpsCsvFile = null;
    _sessionId = null;
    _projectTag = null;
    _configuration = null;
    _startedAt = null;
    _trackPointCount = 0;
    _gpsRowCount = 0;
    return file;
  }

  Future<void> flush() async {
    await _sink?.flush();
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  static String _formatUtc(DateTime utc) {
    final u = utc.toUtc();
    return '${u.year}-${_pad(u.month)}-${_pad(u.day)}T'
        '${_pad(u.hour)}:${_pad(u.minute)}:${_pad(u.second)}Z';
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

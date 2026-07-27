import 'dart:convert';
import 'dart:io';

import 'package:docman/docman.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/run_file_names.dart';

/// Durable data under `/storage/emulated/0/OpenDragy` (all-files access)
/// with optional SAF folder as fallback.
class OpenDragyStorage {
  static const _prefsUriKey = 'open_dragy_data_folder_uri';
  static const _prefsModeKey = 'open_dragy_storage_mode'; // public | saf
  static const _publicRootPath = '/storage/emulated/0/OpenDragy';
  static const _ridesSubdir = 'rides';
  static const _runsSubdir = 'runs';

  /// When public mode is active, rides/runs write here (survives uninstall).
  static String? _publicRidesPath;
  static String? _publicRunsPath;
  static String? _publicRootActive;

  String? _rootUri;
  String _mode = ''; // 'public' | 'saf' | ''

  bool get hasDataFolder =>
      _mode == 'public' || (_rootUri != null && _rootUri!.isNotEmpty);

  bool get isPublicMode => _mode == 'public';

  String? get rootUri => _rootUri;

  String? get publicRootPath =>
      _mode == 'public' ? _publicRootPath : null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(_prefsModeKey) ?? '';
    _rootUri = prefs.getString(_prefsUriKey);

    // After reinstall prefs are empty — if all-files access is already on, reuse /OpenDragy.
    if (_mode.isEmpty && await _hasAllFilesAccess()) {
      await _activatePublicRoot();
      await prefs.setString(_prefsModeKey, 'public');
      return;
    }

    if (_mode == 'public') {
      if (await _hasAllFilesAccess()) {
        await _activatePublicRoot();
      } else {
        _mode = '';
        _clearPublicOverrides();
        await prefs.remove(_prefsModeKey);
      }
    } else if (_mode == 'saf' && _rootUri != null) {
      final status = await DocMan.perms.status(_rootUri!);
      if (status == null || !status.write) {
        _mode = '';
        _rootUri = null;
        await prefs.remove(_prefsUriKey);
        await prefs.remove(_prefsModeKey);
      }
    }
  }

  Future<bool> _hasAllFilesAccess() async {
    if (!Platform.isAndroid) return false;
    return Permission.manageExternalStorage.isGranted;
  }

  Future<void> _activatePublicRoot() async {
    final root = Directory(_publicRootPath);
    await root.create(recursive: true);
    final rides = Directory('${root.path}/$_ridesSubdir');
    final runs = Directory('${root.path}/$_runsSubdir');
    await rides.create(recursive: true);
    await runs.create(recursive: true);
    _publicRootActive = root.path;
    _publicRidesPath = rides.path;
    _publicRunsPath = runs.path;
    _mode = 'public';
  }

  void _clearPublicOverrides() {
    _publicRootActive = null;
    _publicRidesPath = null;
    _publicRunsPath = null;
  }

  /// Request all-files access and create `/OpenDragy` at storage root.
  Future<bool> ensurePublicDataFolder() async {
    if (!Platform.isAndroid) return false;

    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    if (!status.isGranted) {
      // Opens system "Allow access to manage all files" screen on many OEMs.
      await openAppSettings();
      status = await Permission.manageExternalStorage.status;
    }
    if (!status.isGranted) return false;

    await _activatePublicRoot();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsModeKey, 'public');
    await prefs.remove(_prefsUriKey);
    _rootUri = null;

    // Migrate any app-private rides into public folder once.
    await _migrateAppPrivateIntoPublic();
    return true;
  }

  Future<void> _migrateAppPrivateIntoPublic() async {
    if (_publicRidesPath == null || _publicRunsPath == null) return;
    final appDocs = await getApplicationDocumentsDirectory();
    final oldRides = Directory('${appDocs.path}/rides');
    if (await oldRides.exists()) {
      for (final entity in oldRides.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final dest = File('$_publicRidesPath/$name');
        if (!await dest.exists()) {
          await entity.copy(dest.path);
        }
      }
    }
    final oldRuns = Directory('${appDocs.path}/runs_export');
    if (await oldRuns.exists()) {
      for (final entity in oldRuns.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final dest = File('$_publicRunsPath/$name');
        if (!await dest.exists()) {
          await entity.copy(dest.path);
        }
      }
    }
    for (final name in ['garage.json', 'settings.json']) {
      final src = File('${appDocs.path}/$name');
      if (!await src.exists()) continue;
      final dest = File('$_publicRootActive/$name');
      if (!await dest.exists()) {
        await src.copy(dest.path);
      }
    }
  }

  /// Fallback: user-picked SAF folder.
  Future<bool> pickDataFolder() async {
    if (!Platform.isAndroid) return false;
    final picked = await DocMan.pick.directory();
    if (picked == null || !picked.isDirectory) return false;

    _rootUri = picked.uri;
    _mode = 'saf';
    _clearPublicOverrides();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUriKey, _rootUri!);
    await prefs.setString(_prefsModeKey, 'saf');

    await _ensureSafSubdirs(picked);
    await pullAllFromSaf();
    return true;
  }

  /// Preferred entry: try public root first, then SAF.
  Future<bool> setupDataFolder({bool allowSafFallback = true}) async {
    if (await ensurePublicDataFolder()) return true;
    if (allowSafFallback) return pickDataFolder();
    return false;
  }

  Future<DocumentFile?> _rootDir() async {
    if (_rootUri == null) return null;
    try {
      return await DocumentFile.fromUri(_rootUri!);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureSafSubdirs(DocumentFile root) async {
    for (final name in [_ridesSubdir, _runsSubdir]) {
      final existing = await root.find(name);
      if (existing == null) {
        await root.createDirectory(name);
      }
    }
  }

  Future<DocumentFile?> _subdir(String name) async {
    final root = await _rootDir();
    if (root == null) return null;
    await _ensureSafSubdirs(root);
    return root.find(name);
  }

  static Future<Directory> localRidesDirectory() async {
    if (_publicRidesPath != null) {
      final dir = Directory(_publicRidesPath!);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/rides');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> localRunsDirectory() async {
    if (_publicRunsPath != null) {
      final dir = Directory(_publicRunsPath!);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/runs_export');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _jsonBaseDirectory() async {
    if (_publicRootActive != null) {
      return Directory(_publicRootActive!);
    }
    return getApplicationDocumentsDirectory();
  }

  /// In public mode files are already durable; SAF mode copies after stop.
  Future<void> pushSessionFiles(String sessionId) async {
    if (_mode == 'public') return;
    if (_mode != 'saf') return;
    final rides = await _subdir(_ridesSubdir);
    if (rides == null) return;

    final local = await localRidesDirectory();
    final names = <String>[
      '$sessionId.gpx',
      '${sessionId}_gps.csv',
      '${sessionId}_imu.csv',
      '$sessionId.odlog.json',
    ];
    for (final name in names) {
      final file = File('${local.path}/$name');
      if (!await file.exists()) continue;
      try {
        final existing = await rides.find(name);
        if (existing != null) await existing.delete();
        final doc = await DocumentFile.fromUri(file.path);
        if (doc != null) {
          await doc.copyTo(rides.uri, name: name);
        }
      } catch (_) {}
    }
  }

  Future<void> pullRidesFromSaf() async {
    if (_mode == 'public') return;
    if (_mode != 'saf') return;
    final rides = await _subdir(_ridesSubdir);
    if (rides == null) return;
    final local = await localRidesDirectory();

    List<DocumentFile> docs;
    try {
      docs = await rides.listDocuments();
    } catch (_) {
      return;
    }

    for (final doc in docs) {
      if (doc.isDirectory) continue;
      try {
        final cached = await doc.cache();
        if (cached == null) continue;
        final dest = File('${local.path}/${doc.name}');
        await cached.copy(dest.path);
      } catch (_) {}
    }
  }

  Future<void> pushJsonFile(String fileName, Map<String, dynamic> data) async {
    final content = const JsonEncoder.withIndent('  ').convert(data);
    final base = await _jsonBaseDirectory();
    await File('${base.path}/$fileName').writeAsString(content);

    // Also keep app-private mirror for fast Hive-less reads before permission.
    final appDocs = await getApplicationDocumentsDirectory();
    await File('${appDocs.path}/$fileName').writeAsString(content);

    if (_mode == 'saf') {
      final root = await _rootDir();
      if (root == null) return;
      try {
        final existing = await root.find(fileName);
        if (existing != null) await existing.delete();
        await root.createFile(name: fileName, content: content);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> pullJsonFile(String fileName) async {
    if (_mode == 'public' && _publicRootActive != null) {
      final file = File('$_publicRootActive/$fileName');
      if (await file.exists()) {
        try {
          return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    if (_mode == 'saf') {
      final root = await _rootDir();
      if (root != null) {
        try {
          final doc = await root.find(fileName);
          if (doc != null && !doc.isDirectory) {
            final cached = await doc.cache();
            if (cached != null) {
              final text = await cached.readAsString();
              final base = await getApplicationDocumentsDirectory();
              await File('${base.path}/$fileName').writeAsString(text);
              return jsonDecode(text) as Map<String, dynamic>;
            }
          }
        } catch (_) {}
      }
    }

    final base = await getApplicationDocumentsDirectory();
    final file = File('${base.path}/$fileName');
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _localRunDirectory(String runId) async {
    final base = await localRunsDirectory();
    final dir = Directory(
      '${base.path}/${RunFileNames.runDirectory(runId)}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<DocumentFile?> _safRunFolder(String runId) async {
    if (_mode != 'saf') return null;
    final runs = await _subdir(_runsSubdir);
    if (runs == null) return null;
    var folder = await runs.find(runId);
    if (folder == null || !folder.isDirectory) {
      folder = await runs.createDirectory(runId);
    }
    return folder;
  }

  Future<void> _writeSavedRunFile(
    String runId,
    String fileName,
    String content,
  ) async {
    final runDir = await _localRunDirectory(runId);
    await File('${runDir.path}/$fileName').writeAsString(content);

    final safFolder = await _safRunFolder(runId);
    if (safFolder == null) return;
    try {
      final existing = await safFolder.find(fileName);
      if (existing != null) await existing.delete();
      await safFolder.createFile(name: fileName, content: content);
    } catch (_) {}
  }

  Future<void> pushSavedRunJson(String runId, Map<String, dynamic> data) async {
    final content = const JsonEncoder.withIndent('  ').convert(data);
    await _writeSavedRunFile(
      runId,
      RunFileNames.metricsFileName,
      content,
    );
  }

  /// Raw CSV under `runs/{runId}/gps.csv` and `imu.csv`.
  Future<void> pushSavedRunRawCsv({
    required String runId,
    required String gpsCsv,
    required String imuCsv,
  }) async {
    await _writeSavedRunFile(runId, RunFileNames.gpsFileName, gpsCsv);
    await _writeSavedRunFile(runId, RunFileNames.imuFileName, imuCsv);
  }

  Future<void> deleteSavedRunFiles(String runId) async {
    final localDir = await localRunsDirectory();
    final runDir = Directory('${localDir.path}/$runId');
    if (await runDir.exists()) {
      await runDir.delete(recursive: true);
    }
    for (final name in [
      RunFileNames.legacyFlatMetricsJson(runId),
      RunFileNames.legacyFlatGpsCsv(runId),
      RunFileNames.legacyFlatImuCsv(runId),
    ]) {
      final file = File('${localDir.path}/$name');
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (_mode != 'saf') return;
    final runs = await _subdir(_runsSubdir);
    if (runs == null) return;
    for (final name in [
      RunFileNames.legacyFlatMetricsJson(runId),
      RunFileNames.legacyFlatGpsCsv(runId),
      RunFileNames.legacyFlatImuCsv(runId),
    ]) {
      try {
        final doc = await runs.find(name);
        if (doc != null) await doc.delete();
      } catch (_) {}
    }
    try {
      final folder = await runs.find(runId);
      if (folder != null) await folder.delete();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readRunJsonFile(File file) async {
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> pullSavedRuns() async {
    if (_mode == 'saf') {
      final runs = await _subdir(_runsSubdir);
      if (runs != null) {
        final localDir = await localRunsDirectory();
        try {
          final docs = await runs.listDocuments();
          for (final doc in docs) {
            if (doc.isDirectory) {
              final localRunDir = Directory('${localDir.path}/${doc.name}');
              if (!await localRunDir.exists()) {
                await localRunDir.create(recursive: true);
              }
              for (final name in [
                RunFileNames.metricsFileName,
                RunFileNames.gpsFileName,
                RunFileNames.imuFileName,
              ]) {
                final child = await doc.find(name);
                if (child == null || child.isDirectory) continue;
                final cached = await child.cache();
                if (cached == null) continue;
                await cached.copy('${localRunDir.path}/$name');
              }
              continue;
            }
            if (!doc.name.endsWith('.json')) continue;
            final cached = await doc.cache();
            if (cached == null) continue;
            await cached.copy('${localDir.path}/${doc.name}');
          }
        } catch (_) {}
      }
    }

    final localDir = await localRunsDirectory();
    if (!await localDir.exists()) return [];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final entity in localDir.listSync()) {
      if (entity is Directory) {
        final metrics = File(
          '${entity.path}/${RunFileNames.metricsFileName}',
        );
        if (!await metrics.exists()) continue;
        final map = await _readRunJsonFile(metrics);
        if (map == null) continue;
        final id = map['id']?.toString();
        if (id != null) seen.add(id);
        out.add(map);
        continue;
      }
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final map = await _readRunJsonFile(entity);
      if (map == null) continue;
      final id = map['id']?.toString();
      if (id != null && seen.contains(id)) continue;
      out.add(map);
    }
    return out;
  }

  Future<void> deleteSessionFromSaf(String sessionId) async {
    // Public mode: delete local (which is durable) happens in UI.
    if (_mode == 'public') return;
    if (_mode != 'saf') return;
    final rides = await _subdir(_ridesSubdir);
    if (rides == null) return;
    final names = <String>[
      '$sessionId.gpx',
      '${sessionId}_gps.csv',
      '${sessionId}_imu.csv',
      '$sessionId.odlog.json',
    ];
    for (final name in names) {
      try {
        final doc = await rides.find(name);
        if (doc != null) await doc.delete();
      } catch (_) {}
    }
  }

  Future<void> pullAllFromSaf() async {
    await pullRidesFromSaf();
    await pullJsonFile('garage.json');
    await pullJsonFile('settings.json');
    await pullSavedRuns();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ride_recorder.dart';

class RideLogsScreen extends StatefulWidget {
  const RideLogsScreen({super.key});

  @override
  State<RideLogsScreen> createState() => _RideLogsScreenState();
}

class _RideLogsScreenState extends State<RideLogsScreen> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final manifests = await RideRecorder.listSessionManifests();
    final gpxOnly = await RideRecorder.listGpxFiles();
    final files = manifests.isNotEmpty ? manifests : gpxOnly;
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _readManifest(String sessionId) async {
    final dir = await RideRecorder.ridesDirectory();
    final f = File('${dir.path}/$sessionId.odlog.json');
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  Future<List<XFile>> _sessionXFiles(String sessionId) async {
    final dir = await RideRecorder.ridesDirectory();
    final manifest = await _readManifest(sessionId);
    final names = <String>{
      '$sessionId.gpx',
      '${sessionId}_gps.csv',
      '${sessionId}_imu.csv',
      '$sessionId.odlog.json',
    };
    final filesMap = manifest?['files'] as Map<String, dynamic>?;
    if (filesMap != null) {
      for (final name in filesMap.values) {
        if (name is String) names.add(name);
      }
    }
    final out = <XFile>[];
    for (final name in names) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) out.add(XFile(f.path));
    }
    return out;
  }

  Future<void> _shareGpx(String sessionId) async {
    final files = await _sessionXFiles(sessionId);
    final gpx = files.where((f) => f.path.toLowerCase().endsWith('.gpx'));
    if (gpx.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPX file missing')),
        );
      }
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: gpx.toList(), text: 'OpenDragy GPX'),
    );
  }

  Future<void> _shareSession(String sessionId) async {
    final files = await _sessionXFiles(sessionId);
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session files missing')),
        );
      }
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: 'OpenDragy logger session $sessionId',
      ),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete session?'),
        content: Text(
          sessionId,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final dir = await RideRecorder.ridesDirectory();
    final toDelete = await _sessionXFiles(sessionId);
    for (final xf in toDelete) {
      final f = File(xf.path);
      if (await f.exists()) await f.delete();
    }
    // Also remove any leftover named files
    for (final name in [
      '$sessionId.odlog.json',
      '$sessionId.gpx',
      '${sessionId}_gps.csv',
      '${sessionId}_imu.csv',
    ]) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) await f.delete();
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Logger sessions',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Text(
                    'No logger sessions yet.\n'
                    'Tap the timeline icon on the dashboard to record.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(color: Colors.white38),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final sessionId =
                          RideRecorder.sessionIdFromRideFile(file) ??
                              file.uri.pathSegments.last;
                      final modified = file.lastModifiedSync();
                      final sizeKb =
                          (file.lengthSync() / 1024).toStringAsFixed(1);

                      return ListTile(
                        title: Text(
                          sessionId,
                          style: GoogleFonts.robotoMono(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${modified.toLocal()} · $sizeKb KB',
                          style: const TextStyle(color: Colors.white38),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'gpx') _shareGpx(sessionId);
                            if (v == 'session') _shareSession(sessionId);
                            if (v == 'delete') _deleteSession(sessionId);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'gpx',
                              child: Text('Share GPX'),
                            ),
                            PopupMenuItem(
                              value: 'session',
                              child: Text('Share session (GPX+CSV)'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete session',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

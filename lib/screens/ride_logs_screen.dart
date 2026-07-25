import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/dragy_provider.dart';
import '../services/odpkg.dart';
import '../services/ride_recorder.dart';
import '../utils/logger_tags.dart';

class _SessionItem {
  final String sessionId;
  final File manifestFile;
  final Map<String, dynamic> manifest;
  final List<String> tags;

  _SessionItem({
    required this.sessionId,
    required this.manifestFile,
    required this.manifest,
    required this.tags,
  });
}

class RideLogsScreen extends StatefulWidget {
  const RideLogsScreen({super.key});

  @override
  State<RideLogsScreen> createState() => _RideLogsScreenState();
}

class _RideLogsScreenState extends State<RideLogsScreen> {
  List<_SessionItem> _sessions = [];
  List<String> _allTagsRanked = [];
  final Set<String> _selectedFilterTags = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final dragy = context.read<DragyProvider>();
    await dragy.durableStorage.pullRidesFromSaf();
    await dragy.refreshLoggerTagIndex();

    final manifests = await RideRecorder.listSessionManifests();
    final gpxOnly = await RideRecorder.listGpxFiles();
    final items = <_SessionItem>[];
    final tagLists = <List<String>>[];

    if (manifests.isNotEmpty) {
      for (final file in manifests) {
        final sessionId =
            RideRecorder.sessionIdFromRideFile(file) ?? file.uri.pathSegments.last;
        Map<String, dynamic> manifest = {};
        try {
          manifest =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
        final tags = RideRecorder.tagsFromManifest(manifest);
        tagLists.add(tags);
        items.add(
          _SessionItem(
            sessionId: sessionId,
            manifestFile: file,
            manifest: manifest,
            tags: tags,
          ),
        );
      }
    } else {
      for (final file in gpxOnly) {
        final sessionId =
            RideRecorder.sessionIdFromRideFile(file) ?? file.uri.pathSegments.last;
        items.add(
          _SessionItem(
            sessionId: sessionId,
            manifestFile: file,
            manifest: const {},
            tags: const [],
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _sessions = items;
        _allTagsRanked = rankTagsByFrequency(tagLists);
        _loading = false;
      });
    }
  }

  List<_SessionItem> get _filtered {
    final selected = _selectedFilterTags.map((t) => t.toLowerCase()).toSet();
    return _sessions
        .where((s) => sessionMatchesTagFilter(s.tags, selected))
        .toList();
  }

  Future<List<XFile>> _sessionXFiles(String sessionId) async {
    final dir = await RideRecorder.ridesDirectory();
    final manifest = await RideRecorder.readManifest(sessionId);
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
    // Prefer a single .odpkg for PC analyzer; fall back to loose files.
    final pkg = await OdPkg.packSession(sessionId);
    if (pkg != null) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(pkg.path)],
          text: 'OpenDragy session $sessionId (.odpkg)',
        ),
      );
      return;
    }
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
    for (final name in [
      '$sessionId.odlog.json',
      '$sessionId.gpx',
      '${sessionId}_gps.csv',
      '${sessionId}_imu.csv',
    ]) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) await f.delete();
    }
    await context.read<DragyProvider>().durableStorage.deleteSessionFromSaf(
          sessionId,
        );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_allTagsRanked.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in _allTagsRanked)
                            FilterChip(
                              label: Text(
                                tag,
                                style: GoogleFonts.roboto(fontSize: 12),
                              ),
                              selected: _selectedFilterTags.contains(tag),
                              selectedColor:
                                  const Color(0xFFFFBF00).withOpacity(0.25),
                              checkmarkColor: const Color(0xFFFFBF00),
                              backgroundColor: Colors.white10,
                              labelStyle: TextStyle(
                                color: _selectedFilterTags.contains(tag)
                                    ? const Color(0xFFFFBF00)
                                    : Colors.white70,
                              ),
                              side: BorderSide(
                                color: _selectedFilterTags.contains(tag)
                                    ? const Color(0xFFFFBF00)
                                    : Colors.white24,
                              ),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedFilterTags.add(tag);
                                  } else {
                                    _selectedFilterTags.remove(tag);
                                  }
                                });
                              },
                            ),
                          if (_selectedFilterTags.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _selectedFilterTags.clear()),
                              child: Text(
                                'Clear',
                                style: GoogleFonts.roboto(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _sessions.isEmpty
                                ? 'No logger sessions yet.\n'
                                    'Tap the timeline icon on the dashboard to record.'
                                : 'No sessions match the selected tags.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.roboto(color: Colors.white38),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final modified =
                                  item.manifestFile.lastModifiedSync();
                              final vehicle =
                                  item.manifest['vehicle'] as String?;
                              final notes = item.manifest['notes'] as String?;
                              final subtitleParts = <String>[
                                modified.toLocal().toString(),
                                if (vehicle != null && vehicle.isNotEmpty)
                                  vehicle,
                                if (item.tags.isNotEmpty)
                                  item.tags.join(', '),
                                if (notes != null && notes.isNotEmpty) notes,
                              ];

                              return ListTile(
                                title: Text(
                                  item.sessionId,
                                  style: GoogleFonts.robotoMono(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  subtitleParts.join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'gpx') {
                                      _shareGpx(item.sessionId);
                                    }
                                    if (v == 'session') {
                                      _shareSession(item.sessionId);
                                    }
                                    if (v == 'delete') {
                                      _deleteSession(item.sessionId);
                                    }
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
                ),
              ],
            ),
    );
  }
}

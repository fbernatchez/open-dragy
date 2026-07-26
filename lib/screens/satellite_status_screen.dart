import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/dragy_provider.dart';

class SatelliteStatusScreen extends StatelessWidget {
  const SatelliteStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = context.watch<DragyProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'GPS / Map',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _StatsPanel(dragy: dragy),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _MapView(
              latitude: dragy.latitude,
              longitude: dragy.longitude,
              altitude: dragy.altitude,
              speedKmh: dragy.metrics.speedKmh,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final double altitude;
  final double speedKmh;

  const _MapView({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speedKmh,
  });

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  final MapController _mapController = MapController();
  bool _follow = true;
  LatLng? _lastMovedTo;

  static const _fallback = LatLng(49.1951, 16.6068); // Brno-ish default

  LatLng? get _pos {
    final lat = widget.latitude;
    final lon = widget.longitude;
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  @override
  void didUpdateWidget(covariant _MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pos = _pos;
    if (!_follow || pos == null) return;
    final prev = _lastMovedTo;
    if (prev != null &&
        (prev.latitude - pos.latitude).abs() < 1e-6 &&
        (prev.longitude - pos.longitude).abs() < 1e-6) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_follow) return;
      _mapController.move(pos, _mapController.camera.zoom);
      _lastMovedTo = pos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    final center = pos ?? _fallback;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: pos == null ? 6 : 16,
                minZoom: 3,
                maxZoom: 19,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && _follow) {
                    setState(() => _follow = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fb_engineering.open_dragy',
                ),
                if (pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pos,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.navigation,
                          color: Color(0xFFFFBF00),
                          size: 36,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'follow',
                    backgroundColor: _follow
                        ? const Color(0xFFFFBF00)
                        : Colors.black87,
                    onPressed: () {
                      setState(() => _follow = true);
                      final p = _pos;
                      if (p != null) {
                        _mapController.move(p, _mapController.camera.zoom);
                        _lastMovedTo = p;
                      }
                    },
                    child: Icon(
                      Icons.my_location,
                      color: _follow ? Colors.black : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (pos == null)
              const Center(
                child: Text(
                  'Waiting for GPS fix…',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final DragyProvider dragy;

  const _StatsPanel({required this.dragy});

  @override
  Widget build(BuildContext context) {
    final lat = dragy.latitude;
    final lon = dragy.longitude;
    String coord = 'No position yet';
    if (lat != null && lon != null) {
      coord = '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
    }

    final speed = dragy.metrics.speedKmh;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatChip(label: 'SAT', value: '${dragy.satellites}'),
              _StatChip(label: 'Fix', value: dragy.fixTypeLabel),
              _StatChip(
                label: 'hAcc',
                value: dragy.hAccLabel,
              ),
              _StatChip(
                label: 'vAcc',
                value: dragy.vAccLabel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(
                label: 'Speed',
                value: '${speed.toStringAsFixed(1)} km/h',
              ),
              _StatChip(
                label: 'Alt',
                value: dragy.altitude != 0
                    ? '${dragy.altitude.toStringAsFixed(0)} m'
                    : '—',
              ),
              _StatChip(
                label: 'Ready',
                value: dragy.isGpsReady ? 'YES' : 'NO',
              ),
              _StatChip(
                label: 'Link',
                value: dragy.isConnected ? 'BLE' : '—',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            coord,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'NAV-PVT · multi-GNSS + SBAS (EGNOS)',
            style: GoogleFonts.roboto(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.robotoMono(
              color: Colors.amberAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.roboto(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

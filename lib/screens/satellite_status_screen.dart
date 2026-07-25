import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/dragy_provider.dart';
import '../utils/nmea_parser.dart';

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
          'Map',
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
            child: _StatsRow(dragy: dragy),
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
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fb_engineering.open_dragy',
                  maxNativeZoom: 19,
                ),
                if (pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pos,
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.navigation,
                          color: Color(0xFFFFBF00),
                          size: 36,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pos == null
                            ? 'Waiting for GPS fix…'
                            : '${pos.latitude.toStringAsFixed(5)}, '
                                '${pos.longitude.toStringAsFixed(5)}\n'
                                '${widget.speedKmh.toStringAsFixed(1)} km/h · '
                                '${widget.altitude.toStringAsFixed(0)} m',
                        style: GoogleFonts.robotoMono(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _follow ? 'Following' : 'Recenter',
                      onPressed: pos == null
                          ? null
                          : () {
                              setState(() => _follow = true);
                              _mapController.move(pos, 16);
                              _lastMovedTo = pos;
                            },
                      style: IconButton.styleFrom(
                        backgroundColor: _follow
                            ? Colors.amberAccent.withValues(alpha: 0.2)
                            : Colors.white10,
                      ),
                      icon: Icon(
                        Icons.my_location,
                        color: _follow ? Colors.amberAccent : Colors.white54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (pos == null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black38,
                    alignment: Alignment.center,
                    child: Text(
                      'No position yet',
                      style: GoogleFonts.roboto(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final DragyProvider dragy;

  const _StatsRow({required this.dragy});

  @override
  Widget build(BuildContext context) {
    final lat = dragy.latitude;
    final lon = dragy.longitude;
    String coord = '—';
    if (lat != null && lon != null) {
      coord = '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(label: 'SAT', value: '${dragy.satellites}'),
              _StatChip(
                label: 'Fix',
                value: NmeaParser.fixQualityLabel(dragy.fixQuality),
              ),
              _StatChip(
                label: 'HDOP',
                value: dragy.hdop > 0 ? dragy.hdop.toStringAsFixed(1) : '—',
              ),
              _StatChip(
                label: 'Alt',
                value: dragy.altitude != 0
                    ? '${dragy.altitude.toStringAsFixed(0)} m'
                    : '—',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              coord,
              style: GoogleFonts.robotoMono(
                color: Colors.white70,
                fontSize: 12,
              ),
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
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
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

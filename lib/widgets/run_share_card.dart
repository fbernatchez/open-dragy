import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/saved_run.dart';
import '../services/run_share_service.dart';

/// Fixed-width card rendered to PNG for WhatsApp / system share.
class RunShareCard extends StatelessWidget {
  final SavedRun run;
  final ShareCardData data;
  final bool isMetric;
  final bool tempInCelsius;

  const RunShareCard({
    super.key,
    required this.run,
    required this.data,
    required this.isMetric,
    required this.tempInCelsius,
  });

  @override
  Widget build(BuildContext context) {
    final history = run.metrics.history;
    final times = history.map((p) => p.elapsedTime).toList();
    final speeds = history
        .map((p) => isMetric ? p.speedKmh : p.speedKmh * 0.621371)
        .toList();
    final gForces = smoothSeries(history.map((p) => p.gForce).toList(), 7);

    final date = run.dateTime;
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    String? weatherText;
    if (run.temperature != null) {
      final t = tempInCelsius
          ? run.temperature!
          : run.temperature! * 9 / 5 + 32;
      final unit = tempInCelsius ? '°C' : '°F';
      weatherText = '${t.toStringAsFixed(0)}$unit';
      if (run.humidity != null) {
        weatherText = '$weatherText · ${run.humidity!.round()}%';
      }
      if (run.pressureHpa != null) {
        weatherText = '$weatherText · ${run.pressureHpa!.round()} hPa';
      }
    }
    if (run.headwindMps != null) {
      final hw = run.headwindMps!;
      final tag = hw >= 0.15
          ? '+${hw.toStringAsFixed(1)} m/s HW'
          : hw <= -0.15
              ? '${hw.toStringAsFixed(1)} m/s TW'
              : '0 m/s wind';
      weatherText = weatherText == null ? tag : '$weatherText · $tag';
    } else if (run.windSpeedMps != null) {
      final tag = '${run.windSpeedMps!.toStringAsFixed(1)} m/s wind';
      weatherText = weatherText == null ? tag : '$weatherText · $tag';
    }

    final metrics = run.metrics;
    final startAlt = metrics.startAltitude ?? 0.0;
    final endAlt = history.isNotEmpty
        ? (history.last.altitude ?? startAlt)
        : startAlt;
    final elevationDiff = endAlt - startAlt;
    final hasElevation = history.any(
      (p) => p.altitude != null && p.altitude != 0.0,
    );
    String? slopeText;
    String? elevText;
    if (metrics.distanceMeters > 0 && hasElevation) {
      final avgSlope = (elevationDiff / metrics.distanceMeters) * 100;
      slopeText =
          '${avgSlope >= 0 ? '+' : ''}${avgSlope.toStringAsFixed(2)}% slope';
      final displayDiff = isMetric ? elevationDiff : elevationDiff * 3.28084;
      final altUnit = isMetric ? 'm' : 'ft';
      elevText =
          '${displayDiff >= 0 ? '+' : ''}${displayDiff.toStringAsFixed(1)} $altUnit';
    }

    final conditionParts = <String>[
      if (weatherText != null) weatherText,
      if (slopeText != null) slopeText,
      if (elevText != null) elevText,
    ];

    return Container(
      width: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0A), Color(0xFF151515), Color(0xFF0A0A0A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'OpenDragy',
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                dateText,
                style: GoogleFonts.roboto(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (run.vehicleName != null && run.vehicleName!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              run.vehicleName!.trim(),
              style: GoogleFonts.roboto(
                color: const Color(0xFFFFBF00),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            data.primaryTimeText,
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: data.primaryLabel,
                  style: GoogleFonts.roboto(
                    color: const Color(0xFFFFBF00),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                if (data.primaryTrapText != null)
                  TextSpan(
                    text: '  @ ${data.primaryTrapText}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (conditionParts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  if (weatherText != null)
                    Expanded(
                      child: _ConditionChip(
                        icon: Icons.thermostat,
                        label: weatherText,
                      ),
                    ),
                  if (weatherText != null && slopeText != null)
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  if (slopeText != null)
                    Expanded(
                      child: _ConditionChip(
                        icon: Icons.terrain,
                        label: elevText != null
                            ? '$slopeText · $elevText'
                            : slopeText,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (data.rows.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < data.rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 14,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    _ShareRow(row: data.rows[i]),
                  ],
                ],
              ),
            ),
          ],
          if (data.includeChart && times.length >= 2) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'TELEMETRY',
                        style: GoogleFonts.roboto(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      _LegendDot(color: const Color(0xFF29B6F6), label: 'Speed'),
                      const SizedBox(width: 10),
                      _LegendDot(color: const Color(0xFFFF9100), label: 'G'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: ShareTelemetryPainter(
                        times: times,
                        speeds: speeds,
                        gForces: gForces,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'opendragy',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              color: Colors.white24,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ConditionChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFBF00), size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.roboto(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  final ShareMetricRow row;
  const _ShareRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final value = row.trapText != null
        ? '${row.timeText} @ ${row.trapText}'
        : row.timeText;

    return Row(
      children: [
        Expanded(
          child: Text(
            row.label,
            style: GoogleFonts.roboto(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.roboto(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/race_target.dart';
import '../models/saved_run.dart';
import '../screens/share_metrics_sheet.dart';
import '../widgets/run_share_card.dart';

/// Renders a run share card to PNG and opens the system share sheet (WhatsApp, …).
class RunShareService {
  RunShareService._();

  static const double _cardWidth = 360;
  static const double _pixelRatio = 3;

  static Future<void> shareRun({
    required BuildContext context,
    required SavedRun run,
    required bool isMetric,
    required bool useNhraRules,
    required bool tempInCelsius,
  }) async {
    final candidates = listShareCandidates(
      run: run,
      isMetric: isMetric,
      useNhraRules: useNhraRules,
    );
    if (candidates.isEmpty) {
      throw StateError('No shareable metrics on this run');
    }

    final preferredPrimaryId = preferredSharePrimaryId(
      run: run,
      isMetric: isMetric,
      candidates: candidates,
    );

    if (!context.mounted) return;
    final selection = await showShareMetricsPicker(
      context: context,
      candidates: candidates,
      preferredPrimaryId: preferredPrimaryId,
    );
    if (selection == null) return; // cancelled
    if (!context.mounted) return;

    final data = buildShareCardData(
      run: run,
      candidates: candidates,
      selection: selection,
    );

    final overlay = Overlay.of(context);
    final key = GlobalKey();

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -4000,
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _cardWidth,
              child: RunShareCard(
                run: run,
                data: data,
                isMetric: isMetric,
                tempInCelsius: tempInCelsius,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Share card failed to render');
      }
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Share card encode failed');
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'OpenDragy_${_safeFileName(data.primaryLabel)}_${data.primaryTimeText.replaceAll('.', '_')}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png', name: fileName)],
          text: data.shareCaption,
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      entry.remove();
    }
  }

  static String _safeFileName(String label) {
    return label
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

class ShareSelection {
  static const int maxMetrics = 6;

  final String primaryId;
  final List<String> selectedIds;
  final bool includeChart;

  const ShareSelection({
    required this.primaryId,
    required this.selectedIds,
    this.includeChart = true,
  });
}

class ShareMetricCandidate {
  final String id;
  final String label;
  final String timeText;
  final String? trapText;

  const ShareMetricCandidate({
    required this.id,
    required this.label,
    required this.timeText,
    this.trapText,
  });
}

/// Metrics shown on the share card (never includes 0–50 km/h).
class ShareCardData {
  final String primaryLabel;
  final String primaryTimeText;
  final String? primaryTrapText;
  final List<ShareMetricRow> rows;
  final String shareCaption;
  final bool includeChart;

  const ShareCardData({
    required this.primaryLabel,
    required this.primaryTimeText,
    this.primaryTrapText,
    required this.rows,
    required this.shareCaption,
    this.includeChart = true,
  });
}

class ShareMetricRow {
  final String label;
  final String timeText;
  final String? trapText;

  const ShareMetricRow({
    required this.label,
    required this.timeText,
    this.trapText,
  });
}

List<ShareMetricCandidate> listShareCandidates({
  required SavedRun run,
  required bool isMetric,
  required bool useNhraRules,
}) {
  final metrics = run.metrics;
  final nhra = useNhraRules && metrics.rolloutTime1ft != null;
  final out = <ShareMetricCandidate>[];

  for (final test in getCompletedTests(metrics, useNhraRules: nhra)) {
    // Share list is independent of Settings → Result fields visibility.
    if (test.speedUnit != null) {
      final isTestMetric = test.speedUnit == SpeedUnit.kmh;
      if (isTestMetric != isMetric) continue;
    }
    final time =
        getCompletedTimeForCategory(metrics, test.id, useNhraRules: nhra);
    if (time == null) continue;
    final trap =
        getTrapSpeedForCategory(metrics, test.id, useNhraRules: nhra);
    String? trapText;
    if (trap != null) {
      trapText = isMetric
          ? '${trap.toStringAsFixed(0)} km/h'
          : '${(trap * 0.621371).toStringAsFixed(0)} mph';
    }
    out.add(ShareMetricCandidate(
      id: test.id,
      label: test.displayName,
      timeText: '${time.toStringAsFixed(2)}s',
      trapText: trapText,
    ));
  }
  return out;
}

String? preferredSharePrimaryId({
  required SavedRun run,
  required bool isMetric,
  required List<ShareMetricCandidate> candidates,
}) {
  if (candidates.isEmpty) return null;
  final byId = {for (final c in candidates) c.id: c};
  final metrics = run.metrics;

  for (final test in officialTests) {
    if (!byId.containsKey(test.id)) continue;
    if (test.distance != null &&
        metrics.targetDistance != null &&
        (test.distance! - metrics.targetDistance!).abs() < 0.001 &&
        test.distanceUnit?.name == metrics.targetDistanceUnit) {
      return test.id;
    }
    if (test.startSpeed != null &&
        metrics.targetStartSpeed != null &&
        (test.startSpeed! - metrics.targetStartSpeed!).abs() < 0.1 &&
        test.endSpeed != null &&
        metrics.targetEndSpeed != null &&
        (test.endSpeed! - metrics.targetEndSpeed!).abs() < 0.1 &&
        test.speedUnit?.name == metrics.targetSpeedUnit) {
      return test.id;
    }
  }

  final preferred = isMetric
      ? const ['0-100kmh', '1/8mile', '1/4mile', '60ft']
      : const ['0-60mph', '1/8mile', '1/4mile', '60ft'];
  for (final id in preferred) {
    if (byId.containsKey(id)) return id;
  }
  return candidates.first.id;
}

Set<String> defaultShareSelectionIds({
  required List<ShareMetricCandidate> candidates,
  required String? preferredPrimaryId,
}) {
  final preferredOrder = <String>[
    ?preferredPrimaryId,
    '0-100kmh',
    '0-60mph',
    '0-50kmh',
    '1/8mile',
    '60ft',
    '330ft',
    '1/4mile',
    '1000ft',
    '0-200kmh',
    '100-200kmh',
    '60-130mph',
    '1/2mile',
  ];
  final available = {for (final c in candidates) c.id};
  final selected = <String>{};
  for (final id in preferredOrder) {
    if (!available.contains(id)) continue;
    selected.add(id);
    if (selected.length >= ShareSelection.maxMetrics) break;
  }
  if (selected.isEmpty && candidates.isNotEmpty) {
    selected.add(candidates.first.id);
  }
  return selected;
}

String? resolveSharePrimaryId({
  required Set<String> selectedIds,
  required String? preferredPrimaryId,
  required List<ShareMetricCandidate> candidates,
}) {
  if (selectedIds.isEmpty) return null;
  if (preferredPrimaryId != null && selectedIds.contains(preferredPrimaryId)) {
    return preferredPrimaryId;
  }
  for (final c in candidates) {
    if (selectedIds.contains(c.id)) return c.id;
  }
  return selectedIds.first;
}

ShareCardData buildShareCardData({
  required SavedRun run,
  required List<ShareMetricCandidate> candidates,
  required ShareSelection selection,
}) {
  final byId = {for (final c in candidates) c.id: c};
  final primary = byId[selection.primaryId] ??
      byId[selection.selectedIds.first] ??
      candidates.first;

  final rows = <ShareMetricRow>[];
  for (final c in candidates) {
    if (!selection.selectedIds.contains(c.id)) continue;
    if (c.id == primary.id) continue;
    rows.add(ShareMetricRow(
      label: c.label,
      timeText: c.timeText,
      trapText: c.trapText,
    ));
  }

  final vehicle = run.vehicleName?.trim();
  final caption = StringBuffer('OpenDragy');
  if (vehicle != null && vehicle.isNotEmpty) caption.write(' · $vehicle');
  caption.write(' · ${primary.label} ${primary.timeText}');
  if (primary.trapText != null) {
    caption.write(' @ ${primary.trapText}');
  }

  return ShareCardData(
    primaryLabel: primary.label,
    primaryTimeText: primary.timeText,
    primaryTrapText: primary.trapText,
    rows: rows,
    shareCaption: caption.toString(),
    includeChart: selection.includeChart,
  );
}

List<double> smoothSeries(List<double> input, int windowSize) {
  if (input.length < windowSize) return List<double>.from(input);
  final output = <double>[];
  for (var i = 0; i < input.length; i++) {
    final start = (i - windowSize ~/ 2).clamp(0, input.length - 1);
    final end = (i + windowSize ~/ 2).clamp(0, input.length - 1);
    var sum = 0.0;
    var count = 0;
    for (var j = start; j <= end; j++) {
      sum += input[j];
      count++;
    }
    output.add(sum / count);
  }
  return output;
}

/// Compact speed / G painter for the share card.
class ShareTelemetryPainter extends CustomPainter {
  final List<double> times;
  final List<double> speeds;
  final List<double> gForces;

  ShareTelemetryPainter({
    required this.times,
    required this.speeds,
    required this.gForces,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (times.length < 2) return;
    final width = size.width;
    final height = size.height;
    final minX = times.first;
    final maxX = times.last > minX ? times.last : minX + 1.0;
    final maxSpeed = max(10.0, speeds.reduce(max));
    const minG = -0.5;
    const maxG = 1.5;

    double xOf(double t) => (t - minX) / (maxX - minX) * width;
    double ySpeed(double s) => height - (s / maxSpeed).clamp(0.0, 1.0) * height;
    double yG(double g) {
      final pct = ((g - minG) / (maxG - minG)).clamp(0.0, 1.0);
      return height - pct * height;
    }

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(width, y), grid);
    }

    final speedFill = Path()..moveTo(xOf(times.first), height);
    final speedPath = Path()..moveTo(xOf(times.first), ySpeed(speeds.first));
    final gPath = Path()..moveTo(xOf(times.first), yG(gForces.first));
    speedFill.lineTo(xOf(times.first), ySpeed(speeds.first));
    for (var i = 1; i < times.length; i++) {
      final x = xOf(times[i]);
      speedPath.lineTo(x, ySpeed(speeds[i]));
      speedFill.lineTo(x, ySpeed(speeds[i]));
      gPath.lineTo(x, yG(gForces[i]));
    }
    speedFill
      ..lineTo(xOf(times.last), height)
      ..close();

    canvas.drawPath(
      speedFill,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, height),
          [
            const Color(0xFF29B6F6).withValues(alpha: 0.35),
            const Color(0xFF29B6F6).withValues(alpha: 0.02),
          ],
        ),
    );
    canvas.drawPath(
      gPath,
      Paint()
        ..color = const Color(0xFFFF9100).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      speedPath,
      Paint()
        ..color = const Color(0xFF29B6F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant ShareTelemetryPainter oldDelegate) =>
      oldDelegate.times != times ||
      oldDelegate.speeds != speeds ||
      oldDelegate.gForces != gForces;
}

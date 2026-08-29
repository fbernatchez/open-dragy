import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/dragy_provider.dart';
import '../models/saved_run.dart';
import '../models/race_target.dart';
import '../utils/unit_converter.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/share_slip_widget.dart';

class RunDetailScreen extends StatelessWidget {
  final SavedRun run;
  final GlobalKey _boundaryKey = GlobalKey();

  RunDetailScreen({super.key, required this.run});

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day;
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year at $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final run = dragy.savedRuns.firstWhere(
      (r) => r.id == this.run.id,
      orElse: () => this.run,
    );
    final isMetric = dragy.isMetric;
    final tempInCelsius = dragy.tempInCelsius;
    final useNhraRules =
        dragy.useNhraRules && run.metrics.rolloutTime1ft != null;
    final metrics = run.metrics;

    // Collect reached milestones sorted by completion time ascending
    final List<_ReachedMilestone> reachedMilestones = [];

    // 1. Official completed tests
    final completedTests = getCompletedTests(
      metrics,
      useNhraRules: useNhraRules,
    );
    for (final test in completedTests) {
      // Filter out speed targets of the opposite unit system to match user's preference
      if (test.speedUnit != null) {
        final isTestMetric = test.speedUnit == SpeedUnit.kmh;
        if (isTestMetric != isMetric) {
          continue;
        }
      }

      final time = getCompletedTimeForCategory(
        metrics,
        test.id,
        useNhraRules: useNhraRules,
      );
      if (time != null) {
        double sortTime = time;
        if (test.startSpeed != null && test.startSpeed! > 0.0) {
          if (test.speedUnit == SpeedUnit.mph) {
            sortTime = (metrics.time0to60mph ?? 0.0) + time;
          } else {
            sortTime = (metrics.time0to100kmh ?? 0.0) + time;
          }
        }

        reachedMilestones.add(
          _ReachedMilestone(
            label: test.displayName,
            time: time,
            sortTime: sortTime,
            trapSpeed: getTrapSpeedForCategory(
              metrics,
              test.id,
              useNhraRules: useNhraRules,
            ),
          ),
        );
      }
    }

    // 2. Custom interval category if it's an interval run and not an official test
    if (metrics.runMode == 'interval' &&
        metrics.targetStartSpeed != null &&
        metrics.targetEndSpeed != null) {
      bool matchesAny = false;
      for (final test in officialTests) {
        if (test.startSpeed != null &&
            (metrics.targetStartSpeed! - test.startSpeed!).abs() < 0.1 &&
            test.endSpeed != null &&
            (metrics.targetEndSpeed! - test.endSpeed!).abs() < 0.1 &&
            metrics.targetSpeedUnit == test.speedUnit?.name) {
          matchesAny = true;
          break;
        }
      }
      if (!matchesAny) {
        final unit = metrics.targetSpeedUnit ?? (isMetric ? 'kmh' : 'mph');
        final startSpeed = !isMetric
            ? UnitConverter.kmhToMph(metrics.targetStartSpeed!).round()
            : metrics.targetStartSpeed!.round();
        final endSpeed = !isMetric
            ? UnitConverter.kmhToMph(metrics.targetEndSpeed!).round()
            : metrics.targetEndSpeed!.round();
        final customId = 'custom_${startSpeed}_${endSpeed}_$unit';
        final compTime = getCompletedTimeForCategory(
          metrics,
          customId,
          useNhraRules: useNhraRules,
        );
        if (compTime != null) {
          final label = getDisplayLabelForTarget(
            startSpeed: metrics.targetStartSpeed,
            endSpeed: metrics.targetEndSpeed,
            speedUnit: metrics.targetSpeedUnit,
            runMode: 'interval',
          );
          reachedMilestones.add(
            _ReachedMilestone(label: label, time: compTime, sortTime: compTime),
          );
        }
      }
    }

    reachedMilestones.sort((a, b) => a.sortTime.compareTo(b.sortTime));

    final speedMilestones = reachedMilestones
        .where((m) => m.label.contains('mph') || m.label.contains('km/h'))
        .toList();
    final distanceMilestones = reachedMilestones
        .where((m) => !(m.label.contains('mph') || m.label.contains('km/h')))
        .toList();

    // Determine primary display
    String primaryLabel = isMetric ? "0-100 km/h Time" : "0-60 mph Time";
    String primaryTime = "-.--s";

    // Try to find if the run has an active/completed target matching an official test
    OfficialTest? targetTest;
    for (final test in officialTests) {
      if (test.distance != null &&
          metrics.targetDistance != null &&
          (test.distance! - metrics.targetDistance!).abs() < 0.001 &&
          test.distanceUnit?.name == metrics.targetDistanceUnit) {
        targetTest = test;
        break;
      } else if (test.startSpeed != null &&
          metrics.targetStartSpeed != null &&
          (test.startSpeed! - metrics.targetStartSpeed!).abs() < 0.1 &&
          test.endSpeed != null &&
          metrics.targetEndSpeed != null &&
          (test.endSpeed! - metrics.targetEndSpeed!).abs() < 0.1 &&
          test.speedUnit?.name == metrics.targetSpeedUnit) {
        targetTest = test;
        break;
      }
    }

    double? completedTime;
    if (targetTest != null) {
      completedTime = getCompletedTimeForCategory(
        metrics,
        targetTest.id,
        useNhraRules: useNhraRules,
      );
      if (completedTime != null) {
        primaryLabel = "${targetTest.displayName} Time";
      }
    } else if (metrics.runMode == 'interval' &&
        metrics.targetStartSpeed != null &&
        metrics.targetEndSpeed != null) {
      // Custom interval target
      final label = getDisplayLabelForTarget(
        startSpeed: metrics.targetStartSpeed,
        endSpeed: metrics.targetEndSpeed,
        speedUnit: metrics.targetSpeedUnit,
        runMode: 'interval',
      );
      primaryLabel = "$label Time";
      final unit = metrics.targetSpeedUnit ?? (isMetric ? 'kmh' : 'mph');
      final startSpeed = !isMetric
          ? UnitConverter.kmhToMph(metrics.targetStartSpeed!).round()
          : metrics.targetStartSpeed!.round();
      final endSpeed = !isMetric
          ? UnitConverter.kmhToMph(metrics.targetEndSpeed!).round()
          : metrics.targetEndSpeed!.round();
      final customId = 'custom_${startSpeed}_${endSpeed}_$unit';
      completedTime = getCompletedTimeForCategory(
        metrics,
        customId,
        useNhraRules: useNhraRules,
      );
    }

    // Fallback if target is not completed or none was set
    if (completedTime == null) {
      final completed = getCompletedTests(metrics, useNhraRules: useNhraRules);
      double maxTime = -1.0;
      for (final test in completed) {
        if (test.speedUnit != null) {
          final isTestMetric = test.speedUnit == SpeedUnit.kmh;
          if (isTestMetric != isMetric) continue;
        }
        final t = getCompletedTimeForCategory(
          metrics,
          test.id,
          useNhraRules: useNhraRules,
        );
        if (t != null && t > maxTime) {
          maxTime = t;
          completedTime = t;
          primaryLabel = "${test.displayName} Time";
        }
      }
    }

    if (completedTime != null) {
      primaryTime = "${completedTime.toStringAsFixed(2)}s";
    }

    final double startAlt = metrics.startAltitude ?? 0.0;
    final double endAlt = metrics.history.isNotEmpty
        ? (metrics.history.last.altitude ?? startAlt)
        : startAlt;
    final double elevationDiff = endAlt - startAlt;
    final double avgSlope = metrics.distanceMeters > 0
        ? (elevationDiff / metrics.distanceMeters) * 100
        : 0.0;
    final bool isSlopeValid = avgSlope >= -1.0;

    final double displayStartAlt = isMetric
        ? startAlt
        : UnitConverter.metersToFeet(startAlt);
    final double displayEndAlt = isMetric
        ? endAlt
        : UnitConverter.metersToFeet(endAlt);
    final double displayElevationDiff = isMetric
        ? elevationDiff
        : UnitConverter.metersToFeet(elevationDiff);
    final String altUnit = isMetric ? 'm' : 'ft';

    final String fullLabel =
        (useNhraRules &&
            (metrics.runMode == 'drag' || metrics.targetStartSpeed == 0.0))
        ? "$primaryLabel (NHRA rules)"
        : primaryLabel;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Run Details',
          style: GoogleFonts.comfortaa(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.blueAccent),
            onPressed: () => _shareRun(context, fullLabel, primaryTime),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _formatDate(run.dateTime),
                  style: GoogleFonts.roboto(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _showVehicleSelector(context, dragy, run),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_car,
                          color: run.vehicleName != null
                              ? const Color(0xFFFFBF00)
                              : Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          run.vehicleName ?? 'No Vehicle Assigned',
                          style: GoogleFonts.roboto(
                            color: run.vehicleName != null
                                ? const Color(0xFFFFBF00)
                                : Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_outlined,
                          color: run.vehicleName != null
                              ? const Color(0xFFFFBF00)
                              : Colors.white38,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Time Display
                Text(
                  primaryTime,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  fullLabel,
                  style: GoogleFonts.roboto(
                    color: const Color(0xFFFFBF00), // Neon Amber
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 32),
                // Speed Box
                if (speedMilestones.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.speed,
                              color: Color(0xFFFFBF00),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'SPEED',
                              style: GoogleFonts.roboto(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: speedMilestones.map((m) {
                            return _DetailSlipRow(
                              label: m.label,
                              time: m.time,
                              trapSpeed: m.trapSpeed,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Distance Box
                if (distanceMilestones.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.flag_outlined,
                              color: Color(0xFFFFBF00),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'DISTANCE',
                              style: GoogleFonts.roboto(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: distanceMilestones.map((m) {
                            return _DetailSlipRow(
                              label: m.label,
                              time: m.time,
                              trapSpeed: m.trapSpeed,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                TelemetryChart(run: run, isMetric: isMetric),
                const SizedBox(height: 24),
                // Run elevation summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.terrain_outlined,
                            color: Color(0xFFFFBF00),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Elevation & Slope Profile',
                            style: GoogleFonts.roboto(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ProfileStatRow(
                        label: 'Start Altitude',
                        value: '${displayStartAlt.toStringAsFixed(1)} $altUnit',
                      ),
                      _ProfileStatRow(
                        label: 'End Altitude',
                        value: '${displayEndAlt.toStringAsFixed(1)} $altUnit',
                      ),
                      _ProfileStatRow(
                        label: 'Elevation Change',
                        value:
                            '${displayElevationDiff >= 0 ? '+' : ''}${displayElevationDiff.toStringAsFixed(1)} $altUnit',
                        valueColor: displayElevationDiff >= 0
                            ? const Color(0xFF39FF14)
                            : Colors.redAccent,
                      ),
                      _ProfileStatRow(
                        label: 'Average Slope',
                        value:
                            '${avgSlope >= 0 ? '+' : ''}${avgSlope.toStringAsFixed(2)}%',
                        valueColor: isSlopeValid
                            ? const Color(0xFF39FF14)
                            : Colors.redAccent,
                        trailing: isSlopeValid
                            ? const Icon(
                                Icons.check_circle_outline,
                                color: Color(0xFF39FF14),
                                size: 16,
                              )
                            : const Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                      ),
                    ],
                  ),
                ),
                if (run.temperature != null && run.humidity != null) ...[
                  const SizedBox(height: 24),
                  _EnvironmentCard(
                    run: run,
                    tempInCelsius: tempInCelsius,
                    isMetric: isMetric,
                  ),
                ],
                const SizedBox(height: 24),
                _NoteBox(run: run),
              ],
            ),
          ),

          // Hidden off-screen share slip widget
          Positioned(
            left: -10000,
            top: -10000,
            child: RepaintBoundary(
              key: _boundaryKey,
              child: ShareSlipWidget(
                run: run,
                primaryLabel: fullLabel,
                primaryTime: primaryTime,
                isMetric: isMetric,
                tempInCelsius: tempInCelsius,
                useNhraRules: useNhraRules,
                speedMilestones: speedMilestones
                    .map(
                      (m) => ReachedMilestone(
                        label: m.label,
                        time: m.time,
                        trapSpeed: m.trapSpeed,
                      ),
                    )
                    .toList(),
                distanceMilestones: distanceMilestones
                    .map(
                      (m) => ReachedMilestone(
                        label: m.label,
                        time: m.time,
                        trapSpeed: m.trapSpeed,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRun(
    BuildContext context,
    String primaryLabel,
    String primaryTime,
  ) async {
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/opendragy_run_${run.id}.png');
      await file.writeAsBytes(pngBytes);

      final vehicle = run.vehicleName ?? 'Unknown Vehicle';
      final text =
          'OpenDragy Run\n$primaryLabel: $primaryTime\nVehicle: $vehicle\n\nGenerated by OpenDragy';

      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (e) {
      debugPrint('Error sharing image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sharing: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    showDialog(
      context: context,
      builder: (diagContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete Run', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete this run from your history?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(diagContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Provider.of<DragyProvider>(
                context,
                listen: false,
              ).deleteRun(run.id);
              Navigator.pop(diagContext); // Pop dialog
              Navigator.pop(context); // Pop detail screen
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleSelector(
    BuildContext context,
    DragyProvider dragy,
    SavedRun currentRun,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.only(
            top: 24,
            bottom: 32,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign Vehicle',
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (dragy.vehicles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Your garage is empty.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ...dragy.vehicles.map((v) {
                  final isSelected = v.id == currentRun.vehicleId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.directions_car,
                      color: isSelected
                          ? const Color(0xFFFFBF00)
                          : Colors.white54,
                    ),
                    title: Text(
                      v.displayName,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFFFBF00)
                            : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFFFFBF00))
                        : null,
                    onTap: () {
                      dragy.updateRunVehicle(
                        currentRun.id,
                        v.id,
                        v.displayName,
                      );
                      Navigator.pop(ctx);
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _DetailSlipRow extends StatelessWidget {
  final String label;
  final double? time;
  final double? trapSpeed;

  const _DetailSlipRow({required this.label, this.time, this.trapSpeed});

  @override
  Widget build(BuildContext context) {
    if (time == null) return const SizedBox.shrink();

    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;

    String speedDisplay = '';
    if (trapSpeed != null) {
      if (!isMetric) {
        final speedMph = UnitConverter.kmhToMph(trapSpeed!);
        speedDisplay =
            '${time!.toStringAsFixed(2)}s@${speedMph.toStringAsFixed(2)} mph';
      } else {
        speedDisplay =
            '${time!.toStringAsFixed(2)}s@${trapSpeed!.toStringAsFixed(2)} km/h';
      }
    } else {
      speedDisplay = '${time!.toStringAsFixed(2)}s';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF39FF14),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.roboto(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                speedDisplay,
                style: GoogleFonts.robotoMono(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const _ProfileStatRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.roboto(color: Colors.white54, fontSize: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.robotoMono(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _NoteBox extends StatefulWidget {
  final SavedRun run;

  const _NoteBox({required this.run});

  @override
  State<_NoteBox> createState() => _NoteBoxState();
}

class _NoteBoxState extends State<_NoteBox> {
  late TextEditingController _controller;
  Timer? _debounce;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.run.notes ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onNotesChanged(String text) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    setState(() {
      _isSaving = true;
    });
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (mounted) {
        await Provider.of<DragyProvider>(
          context,
          listen: false,
        ).updateRunNotes(widget.run.id, text);
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.note_alt_outlined,
                    color: Color(0xFFFFBF00),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Notes',
                    style: GoogleFonts.roboto(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSaving ? 1.0 : 0.0,
                child: _isSaving
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFFFBF00),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Saving...',
                            style: GoogleFonts.roboto(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onChanged: _onNotesChanged,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 14),
            cursorColor: const Color(0xFFFFBF00),
            decoration: InputDecoration(
              hintText:
                  'Add notes (e.g., tire pressure, launch RPM, track prep)...',
              hintStyle: GoogleFonts.roboto(
                color: Colors.white38,
                fontSize: 14,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  final SavedRun run;
  final bool tempInCelsius;
  final bool isMetric;

  const _EnvironmentCard({
    required this.run,
    required this.tempInCelsius,
    required this.isMetric,
  });

  @override
  Widget build(BuildContext context) {
    final startAlt = run.metrics.startAltitude ?? 0.0;
    final tempC = run.temperature ?? 15.0;
    final humidity = run.humidity ?? 0.0;

    final daMeters = UnitConverter.calculateDensityAltitude(startAlt, tempC);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                color: Color(0xFFFFBF00),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Weather & Environment',
                style: GoogleFonts.roboto(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProfileStatRow(
            label: 'Temperature',
            value: tempInCelsius
                ? '${tempC.toStringAsFixed(1)}°C'
                : '${UnitConverter.celsiusToFahrenheit(tempC).toStringAsFixed(0)}°F',
          ),
          _ProfileStatRow(
            label: 'Humidity',
            value: '${humidity.toStringAsFixed(0)}%',
          ),
          _ProfileStatRow(
            label: 'Density Altitude',
            value: isMetric
                ? '${daMeters.toStringAsFixed(0)}m'
                : '${UnitConverter.metersToFeet(daMeters).toStringAsFixed(0)}ft',
          ),
        ],
      ),
    );
  }
}

class _ReachedMilestone {
  final String label;
  final double time;
  final double sortTime;
  final double? trapSpeed;

  _ReachedMilestone({
    required this.label,
    required this.time,
    required this.sortTime,
    this.trapSpeed,
  });
}

class TelemetryChart extends StatefulWidget {
  final SavedRun run;
  final bool isMetric;

  const TelemetryChart({super.key, required this.run, required this.isMetric});

  @override
  State<TelemetryChart> createState() => _TelemetryChartState();
}

class _TelemetryChartState extends State<TelemetryChart> {
  int? _selectedIndex;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;
  bool _isScrubbing = false;
  PlayerState _playerState = PlayerState.stopped;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _stateSubscription;
  Timer? _uiTimer;
  double _interpolatedChartSec = 0.0;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _setupAudio();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_isPlayingAudio && _lastUpdate != null) {
        final now = DateTime.now();
        final delta = now.difference(_lastUpdate!).inMilliseconds / 1000.0;
        _lastUpdate = now;
        _interpolatedChartSec += delta;
        _updateChartSelection(_interpolatedChartSec);
      }
    });
  }

  void _updateChartSelection(double chartSec) {
    if (chartSec >= 0) {
      final history = widget.run.metrics.history;
      if (history.isNotEmpty && mounted) {
        int bestIdx = 0;
        double minDiff = double.infinity;
        for (int i = 0; i < history.length; i++) {
          final diff = (history[i].elapsedTime - chartSec).abs();
          if (diff < minDiff) {
            minDiff = diff;
            bestIdx = i;
          }
        }
        if (_selectedIndex != bestIdx) {
          setState(() {
            _selectedIndex = bestIdx;
          });
        }
      }
    }
  }

  void _setupAudio() {
    if (widget.run.audioFilePath != null) {
      final file = File(widget.run.audioFilePath!);
      if (file.existsSync()) {
        _audioPlayer.setSourceDeviceFile(widget.run.audioFilePath!);

        _positionSubscription = _audioPlayer.onPositionChanged.listen((
          position,
        ) {
          if (_isScrubbing || !_isPlayingAudio) return;
          final offset = widget.run.audioStartOffset ?? 0.0;
          final audioSec = position.inMilliseconds / 1000.0;
          _interpolatedChartSec = audioSec - offset;
          _lastUpdate = DateTime.now();
          _updateChartSelection(_interpolatedChartSec);
        });

        _stateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
          if (mounted) {
            setState(() {
              _playerState = state;
              _isPlayingAudio = state == PlayerState.playing;
              if (_isPlayingAudio) {
                _lastUpdate = DateTime.now();
              } else {
                _lastUpdate = null;
                if (state == PlayerState.completed) {
                  _selectedIndex = null;
                }
              }
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  List<double> _smoothList(List<double> input, int windowSize) {
    if (input.length < windowSize) return List.from(input);
    final List<double> output = [];
    for (int i = 0; i < input.length; i++) {
      int start = (i - windowSize ~/ 2).clamp(0, input.length - 1);
      int end = (i + windowSize ~/ 2).clamp(0, input.length - 1);
      double sum = 0.0;
      int count = 0;
      for (int j = start; j <= end; j++) {
        sum += input[j];
        count++;
      }
      output.add(sum / count);
    }
    return output;
  }

  void _handleTouch(Offset localPosition, double containerWidth) {
    if (!_isScrubbing) {
      _isScrubbing = true;
    }
    final history = widget.run.metrics.history;
    if (history.isEmpty) return;

    final double chartWidth = containerWidth - 32;
    final double relativeX = localPosition.dx;
    final double pct = (relativeX / chartWidth).clamp(0.0, 1.0);
    final int index = (pct * (history.length - 1)).round();

    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _endScrub() {
    _isScrubbing = false;
    if (_selectedIndex != null && widget.run.audioFilePath != null) {
      final history = widget.run.metrics.history;
      if (_selectedIndex! < history.length) {
        final chartSec = history[_selectedIndex!].elapsedTime;
        final offset = widget.run.audioStartOffset ?? 0.0;
        final audioSec = chartSec + offset;
        if (audioSec >= 0) {
          _audioPlayer.seek(Duration(milliseconds: (audioSec * 1000).round()));
          setState(() {
            _interpolatedChartSec = chartSec;
            _lastUpdate = DateTime.now();
          });
        }
      }
    }
    setState(() {
      _selectedIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.run.metrics.history;
    if (history.length < 2) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            const Icon(Icons.show_chart, color: Colors.white24, size: 40),
            const SizedBox(height: 8),
            Text(
              'No telemetry data recorded for this run.',
              style: GoogleFonts.roboto(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isMetric = widget.isMetric;
    final times = history.map((p) => p.elapsedTime).toList();
    final speeds = history
        .map((p) => isMetric ? p.speedKmh : UnitConverter.kmhToMph(p.speedKmh))
        .toList();

    // The physics engine natively shifts the G-force to align with GPS latency.
    final rawGForces = history.map((p) => p.gForce).toList();
    final gForces = _smoothList(rawGForces, 7);

    final double startAltitude = widget.run.metrics.startAltitude ?? 0.0;
    final rawElevations = history.map((p) {
      final double currentAlt = p.altitude ?? startAltitude;
      final double diff = currentAlt - startAltitude;
      return isMetric ? diff : UnitConverter.metersToFeet(diff);
    }).toList();
    final elevations = _smoothList(rawElevations, 9);

    // Check if elevation data is present (non-null and not all zero)
    final bool hasElevation = history.any(
      (p) => p.altitude != null && p.altitude != 0.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Scrub HUD
              _buildHud(times, speeds, gForces, elevations, hasElevation),
              const SizedBox(height: 16),
              // Legend
              _buildLegend(hasElevation),
              const SizedBox(height: 16),
              // Chart Area
              GestureDetector(
                onPanStart: (details) =>
                    _handleTouch(details.localPosition, width),
                onPanUpdate: (details) =>
                    _handleTouch(details.localPosition, width),
                onPanEnd: (_) => _endScrub(),
                onPanCancel: () => _endScrub(),
                onTapDown: (details) =>
                    _handleTouch(details.localPosition, width),
                onTapUp: (_) => _endScrub(),
                child: CustomPaint(
                  size: const Size(double.infinity, 180),
                  painter: TelemetryChartPainter(
                    times: times,
                    speeds: speeds,
                    gForces: gForces,
                    elevations: elevations,
                    hasElevation: hasElevation,
                    isMetric: isMetric,
                    selectedIndex: _selectedIndex,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHud(
    List<double> times,
    List<double> speeds,
    List<double> gForces,
    List<double> elevations,
    bool hasElevation,
  ) {
    if (_selectedIndex != null && _selectedIndex! < times.length) {
      final int idx = _selectedIndex!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.roboto(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Scrubbing Telemetry',
                style: GoogleFonts.roboto(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _buildAudioButton(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HudStat(
                label: 'Time',
                value: '${times[idx].toStringAsFixed(2)}s',
                valueColor: Colors.white,
              ),
              _HudStat(
                label: 'Speed',
                value: speeds[idx].toStringAsFixed(2),
                valueColor: const Color(0xFF29B6F6), // Cyan
              ),
              _HudStat(
                label: 'Accel',
                value: '${gForces[idx].toStringAsFixed(2)}G',
                valueColor: const Color(0xFFFF9100), // Orange
              ),
              if (hasElevation)
                _HudStat(
                  label: 'Height',
                  value:
                      '${elevations[idx] >= 0 ? '+' : ''}${elevations[idx].toStringAsFixed(1)}',
                  valueColor: const Color(0xFF66BB6A), // Green
                ),
            ],
          ),
        ],
      );
    }

    // Default: Summary metrics
    final double maxSpeed = speeds.isNotEmpty ? speeds.reduce(max) : 0.0;
    final double maxG = gForces.isNotEmpty ? gForces.reduce(max) : 0.0;
    final double minG = gForces.isNotEmpty ? gForces.reduce(min) : 0.0;
    final double elevDiff = elevations.isNotEmpty
        ? (elevations.last - elevations.first)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'TELEMETRY GRAPH',
              style: GoogleFonts.roboto(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            _buildAudioButton(),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _HudStat(
              label: 'Max Speed',
              value: maxSpeed.toStringAsFixed(2),
              valueColor: const Color(0xFF29B6F6),
            ),
            _HudStat(
              label: 'Max Accel',
              value: '${maxG.toStringAsFixed(2)}G',
              valueColor: const Color(0xFFFF9100),
            ),
            _HudStat(
              label: 'Min Accel',
              value: '${minG.toStringAsFixed(2)}G',
              valueColor: const Color(0xFFFF9100).withOpacity(0.7),
            ),
            if (hasElevation)
              _HudStat(
                label: 'Elev Change',
                value:
                    '${elevDiff >= 0 ? '+' : ''}${elevDiff.toStringAsFixed(1)}',
                valueColor: const Color(0xFF66BB6A),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioButton() {
    if (widget.run.audioFilePath == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () async {
        if (_isPlayingAudio) {
          _audioPlayer.pause();
        } else {
          if (_playerState == PlayerState.completed) {
            await _audioPlayer.stop();
            await _audioPlayer.setSourceDeviceFile(widget.run.audioFilePath!);
          }

          if (_selectedIndex != null) {
            final history = widget.run.metrics.history;
            final chartSec = _selectedIndex! < history.length
                ? history[_selectedIndex!].elapsedTime
                : 0.0;
            final offset = widget.run.audioStartOffset ?? 0.0;
            await _audioPlayer.seek(
              Duration(milliseconds: ((chartSec + offset) * 1000).round()),
            );
            if (mounted) {
              setState(() {
                _interpolatedChartSec = chartSec;
                _lastUpdate = DateTime.now();
              });
            }
          } else {
            final history = widget.run.metrics.history;
            final isAtEnd =
                history.isNotEmpty &&
                _interpolatedChartSec >= history.last.elapsedTime;
            final isCompleted = _playerState == PlayerState.completed;
            final currentPos = await _audioPlayer.getCurrentPosition();

            if (isAtEnd ||
                isCompleted ||
                currentPos == null ||
                currentPos.inMilliseconds < 100) {
              final offset = widget.run.audioStartOffset ?? 0.0;
              await _audioPlayer.seek(
                Duration(milliseconds: (offset * 1000).round()),
              );
              if (mounted) {
                setState(() {
                  _selectedIndex = 0;
                  _interpolatedChartSec = 0.0;
                  _lastUpdate = DateTime.now();
                });
              }
            } else {
              if (mounted) {
                setState(() {
                  _lastUpdate = DateTime.now();
                });
              }
            }
          }
          await _audioPlayer.resume();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isPlayingAudio
              ? const Color(0xFF1565C0).withOpacity(0.5)
              : const Color(0xFF1565C0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              _isPlayingAudio ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _isPlayingAudio ? 'PAUSE' : 'PLAY',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(bool hasElevation) {
    final speedUnit = widget.isMetric ? 'km/h' : 'mph';
    final heightUnit = widget.isMetric ? 'm' : 'ft';
    return Row(
      children: [
        _LegendItem(
          color: const Color(0xFF29B6F6),
          label: 'Speed ($speedUnit)',
        ),
        const SizedBox(width: 16),
        _LegendItem(color: const Color(0xFFFF9100), label: 'Accel (G)'),
        if (hasElevation) ...[
          const SizedBox(width: 16),
          _LegendItem(
            color: const Color(0xFF66BB6A),
            label: 'Height ($heightUnit)',
          ),
        ],
      ],
    );
  }
}

class _HudStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _HudStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.roboto(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.robotoMono(
            color: valueColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.roboto(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class TelemetryChartPainter extends CustomPainter {
  final List<double> times;
  final List<double> speeds;
  final List<double> gForces;
  final List<double> elevations;
  final bool hasElevation;
  final bool isMetric;
  final int? selectedIndex;

  TelemetryChartPainter({
    required this.times,
    required this.speeds,
    required this.gForces,
    required this.elevations,
    required this.hasElevation,
    required this.isMetric,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (times.isEmpty) return;

    final double width = size.width;
    final double height = size.height;

    // Bounds for X axis (Time)
    final double minX = times.first;
    final double maxX = times.last > minX ? times.last : minX + 1.0;

    // Bounds for Speed (Y axis 1)
    final double maxSpeed = speeds.isNotEmpty ? speeds.reduce(max) : 10.0;
    final double minSpeed = 0.0; // speed always starts at 0

    // Bounds for G-Force (Y axis 2)
    final double minG = -0.5;
    final double maxG = 1.5;

    // Bounds for Height/Elevation (Y axis 3)
    double minAlt = isMetric ? -15.0 : -50.0;
    double maxAlt = isMetric ? 15.0 : 50.0;
    if (elevations.isNotEmpty) {
      double dataMin = elevations.reduce(min);
      double dataMax = elevations.reduce(max);
      double altRange = dataMax - dataMin;
      final double minRange = isMetric ? 30.0 : 100.0;
      if (altRange < minRange) {
        final double center = (dataMax + dataMin) / 2;
        minAlt = center - (minRange / 2);
        maxAlt = center + (minRange / 2);
      } else {
        minAlt = dataMin - (altRange * 0.1);
        maxAlt = dataMax + (altRange * 0.1);
      }
    }

    // Drawing helper functions to map values to coordinates
    double getX(double t) {
      return (t - minX) / (maxX - minX) * width;
    }

    double getYSpeed(double s) {
      final double range = maxSpeed - minSpeed;
      final double pct = range > 0 ? (s - minSpeed) / range : 0.5;
      return height - (pct * height);
    }

    double getYG(double g) {
      final double range = maxG - minG;
      final double pct = range > 0 ? (g - minG) / range : 0.5;
      return height - (pct * height);
    }

    double getYAlt(double alt) {
      final double range = maxAlt - minAlt;
      final double pct = range > 0 ? (alt - minAlt) / range : 0.5;
      return height - (pct * height);
    }

    // Draw Grid Lines (horizontal)
    final int gridLinesCount = 4;
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= gridLinesCount; i++) {
      final double y = height * i / gridLinesCount;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // Draw curves
    final Path speedPath = Path();
    final Path speedFillPath = Path();
    final Path gForcePath = Path();
    final Path elevationPath = Path();

    // Start paths
    if (times.isNotEmpty) {
      speedPath.moveTo(getX(times.first), getYSpeed(speeds.first));
      speedFillPath.moveTo(getX(times.first), height); // bottom start
      speedFillPath.lineTo(getX(times.first), getYSpeed(speeds.first));

      gForcePath.moveTo(getX(times.first), getYG(gForces.first));
      if (hasElevation) {
        elevationPath.moveTo(getX(times.first), getYAlt(elevations.first));
      }

      for (int i = 1; i < times.length; i++) {
        final double x = getX(times[i]);
        speedPath.lineTo(x, getYSpeed(speeds[i]));
        speedFillPath.lineTo(x, getYSpeed(speeds[i]));

        gForcePath.lineTo(x, getYG(gForces[i]));
        if (hasElevation) {
          elevationPath.lineTo(x, getYAlt(elevations[i]));
        }
      }

      // Close speed fill path at the bottom right
      speedFillPath.lineTo(getX(times.last), height);
      speedFillPath.close();
    }

    // 1. Draw Speed Fill Gradient (Robinhood style)
    if (times.isNotEmpty) {
      final Paint speedFillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF29B6F6).withOpacity(0.15),
            const Color(0xFF29B6F6).withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, width, height))
        ..style = PaintingStyle.fill;
      canvas.drawPath(speedFillPath, speedFillPaint);
    }

    // 2. Draw Speed Line
    final Paint speedPaint = Paint()
      ..color =
          const Color(0xFF29B6F6) // Cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;
    canvas.drawPath(speedPath, speedPaint);

    // 3. Draw Height / Elevation Line
    if (hasElevation) {
      final Paint elevationPaint = Paint()
        ..color =
            const Color(0xFF66BB6A) // Green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..isAntiAlias = true;
      canvas.drawPath(elevationPath, elevationPaint);
    }

    // 4. Draw G-Force Line
    final Paint gForcePaint = Paint()
      ..color =
          const Color(0xFFFF9100) // Orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..isAntiAlias = true;
    canvas.drawPath(gForcePath, gForcePaint);

    // 5. Draw Interactive Cursor and Scrub Points
    if (selectedIndex != null && selectedIndex! < times.length) {
      final int idx = selectedIndex!;
      final double x = getX(times[idx]);

      // Vertical line
      final Paint cursorLinePaint = Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, height), cursorLinePaint);

      // Draw intersection dots
      void drawDot(double y, Color color) {
        final Paint borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        final Paint dotPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(x, y), 5.0, borderPaint);
        canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
      }

      // Draw dot on speed
      drawDot(getYSpeed(speeds[idx]), const Color(0xFF29B6F6));

      // Draw dot on gforce
      drawDot(getYG(gForces[idx]), const Color(0xFFFF9100));

      // Draw dot on elevation
      if (hasElevation) {
        drawDot(getYAlt(elevations[idx]), const Color(0xFF66BB6A));
      }
    }
  }

  @override
  bool shouldRepaint(covariant TelemetryChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isMetric != isMetric ||
        oldDelegate.times != times ||
        oldDelegate.speeds != speeds ||
        oldDelegate.gForces != gForces ||
        oldDelegate.elevations != elevations;
  }
}

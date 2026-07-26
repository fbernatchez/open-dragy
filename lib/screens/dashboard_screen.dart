import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import '../models/race_target.dart';
import '../models/race_metrics.dart';
import '../widgets/device_selector_modal.dart';
import 'run_history_screen.dart';
import 'garage_screen.dart';
import 'settings_screen.dart';
import 'ride_logs_screen.dart';
import 'satellite_status_screen.dart';
import '../widgets/logger_tags_input.dart';
import '../widgets/finish_celebration_overlay.dart';
import '../models/app_cues.dart';
import '../utils/logger_tags.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _loggerNotesController = TextEditingController();
  bool _loggerFieldsSynced = false;
  bool _storagePromptScheduled = false;
  int _previousMilestoneCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAskStorageOnLaunch();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _loggerNotesController.dispose();
    super.dispose();
  }

  Future<void> _maybeAskStorageOnLaunch() async {
    if (_storagePromptScheduled) return;
    _storagePromptScheduled = true;
    // Let provider finish durable bootstrap first.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final dragy = context.read<DragyProvider>();
    if (dragy.hasDurableDataFolder) return;
    await _ensureDurableFolder(context, dragy);
  }

  Future<void> _ensureDurableFolder(BuildContext context, DragyProvider dragy) async {
    if (dragy.hasDurableDataFolder) return;
    final pick = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Save data on phone'),
        content: const Text(
          'OpenDragy needs access to files to create the OpenDragy folder '
          'at storage root. Sessions, garage and runs will survive uninstall.\n\n'
          'Allow “All files access” on the next screen.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow & create'),
          ),
        ],
      ),
    );
    if (pick == true && context.mounted) {
      final ok = await dragy.pickDurableDataFolder();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? (dragy.usesPublicDataFolder
                      ? 'Using ${dragy.durableDataFolderPath}'
                      : 'Data folder linked.')
                  : 'Storage access not granted.',
            ),
          ),
        );
      }
    }
  }

  void _showDeviceSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.8,
        child: DeviceSelectorModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;
    final isConnected = dragy.isConnected;
    final metrics = dragy.metrics;

    if (dragy.isLoggerMode && !_loggerFieldsSynced) {
      _loggerNotesController.text = dragy.loggerNotes;
      _loggerFieldsSynced = true;
      unawaited(dragy.refreshLoggerTagIndex());
    } else if (!dragy.isLoggerMode) {
      _loggerFieldsSynced = false;
    }

    // Determine the main highlighted time or status message
    String mainTime = "0.00s";
    double fontSize = 80.0;
    Color textColor = Colors.white;
    String statusKey = "ready";

    if (dragy.isLoggerMode) {
      if (!isConnected) {
        mainTime = "Logger — connect";
        fontSize = 32.0;
        textColor = Colors.white38;
        statusKey = "logger_start";
      } else if (dragy.isRideRecording) {
        mainTime = "REC ${dragy.rideTrackPointCount}";
        fontSize = 48.0;
        textColor = Colors.redAccent;
        statusKey = "logger_rec";
      } else {
        mainTime = "Logger ready";
        fontSize = 36.0;
        textColor = Colors.white70;
        statusKey = "logger_wait";
      }
    } else if (!isConnected) {
      mainTime = "Disconnected";
      fontSize = 40.0;
      textColor = Colors.white38;
      statusKey = "disconnected";
    } else if (metrics.isRunning) {
      mainTime = "${dragy.liveElapsedTime.toStringAsFixed(2)}s";
      fontSize = 80.0;
      textColor = Colors.white;
      statusKey = "running";
    } else {
      double? completedTime;
      if (dragy.runMode == 'interval') {
        String intervalId = dragy.activeIntervalTarget.id;
        if (dragy.activeIntervalTarget == RaceIntervalTarget.custom) {
          final unit = isMetric ? 'kmh' : 'mph';
          intervalId = 'custom_${dragy.customIntervalStartSpeed.round()}_${dragy.customIntervalEndSpeed.round()}_$unit';
        }
        completedTime = getCompletedTimeForCategory(metrics, intervalId, useNhraRules: dragy.useNhraRules);
      } else {
        final completed = getCompletedTests(metrics, useNhraRules: dragy.useNhraRules);
        double maxTime = -1.0;
        for (final test in completed) {
          if (test.speedUnit != null) {
            final isTestMetric = test.speedUnit == SpeedUnit.kmh;
            if (isTestMetric != isMetric) {
              continue;
            }
          }
          final t = getCompletedTimeForCategory(metrics, test.id, useNhraRules: dragy.useNhraRules);
          if (t != null && t > maxTime) {
            maxTime = t;
            completedTime = t;
          }
        }
      }

      if (completedTime != null) {
        mainTime = "${completedTime.toStringAsFixed(2)}s";
        fontSize = 80.0;
        textColor = Colors.white;
        statusKey = "finished";
      } else {
        final bool isGpsReady =
            dragy.satellites >= 4 && dragy.hdop > 0.0 && dragy.hdop <= 2.0;
        if (!isGpsReady) {
          mainTime = "Waiting for GPS";
          fontSize = 35.0;
          textColor = Colors.amberAccent;
          statusKey = "waiting_gps";
        } else if (dragy.isArmed) {
          if (dragy.runMode == 'drag' && metrics.speedKmh > 0.0) {
            mainTime = "Stop";
            fontSize = 60.0;
            textColor = Colors.redAccent;
            statusKey = "stop";
          } else {
            mainTime = dragy.runMode == 'drag'
                ? "Awaiting Launch"
                : "Awaiting Speed";
            fontSize = 32.0;
            textColor = const Color(0xFFFFBF00);
            statusKey = "armed";
          }
        } else {
          mainTime = "Disarmed";
          fontSize = 50.0;
          textColor = Colors.white54;
          statusKey = "disarmed";
        }
      }
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

    // Collect reached milestones sorted by completion time ascending
    final List<_ReachedMilestone> reachedMilestones = [];

    if (dragy.runMode == 'drag') {
      final completed = getCompletedTests(metrics, useNhraRules: dragy.useNhraRules);
      for (final test in completed) {
        if (test.speedUnit != null) {
          final isTestMetric = test.speedUnit == SpeedUnit.kmh;
          if (isTestMetric != isMetric) {
            continue;
          }
        }

        reachedMilestones.add(
          _ReachedMilestone(
            label: test.displayName,
            time: getCompletedTimeForCategory(metrics, test.id, useNhraRules: dragy.useNhraRules)!,
            sortTime: getCompletedTimeForCategory(metrics, test.id, useNhraRules: dragy.useNhraRules)!,
            trapSpeed: getTrapSpeedForCategory(metrics, test.id, useNhraRules: dragy.useNhraRules),
          ),
        );
      }
    } else {
      final completed = getCompletedTests(metrics, useNhraRules: dragy.useNhraRules);
      if (completed.isNotEmpty) {
        final test = completed.first;
        final time =
            getCompletedTimeForCategory(metrics, test.id, useNhraRules: dragy.useNhraRules) ??
            metrics.elapsedTime;
        reachedMilestones.add(
          _ReachedMilestone(
            label: test.displayName,
            time: time,
            sortTime: time,
          ),
        );
      } else if (!metrics.isRunning &&
          metrics.history.isNotEmpty &&
          metrics.elapsedTime > 0 &&
          metrics.targetStartSpeed != null &&
          metrics.targetEndSpeed != null) {
        final label = getDisplayLabelForTarget(
          startSpeed: metrics.targetStartSpeed,
          endSpeed: metrics.targetEndSpeed,
          speedUnit: metrics.targetSpeedUnit,
          runMode: 'interval',
        );
        reachedMilestones.add(
          _ReachedMilestone(
            label: label,
            time: metrics.elapsedTime,
            sortTime: metrics.elapsedTime,
          ),
        );
      }
    }

    reachedMilestones.sort((a, b) => a.sortTime.compareTo(b.sortTime));

    final currentMilestoneCount = reachedMilestones.length;
    if (currentMilestoneCount > _previousMilestoneCount) {
      _previousMilestoneCount = currentMilestoneCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else if (currentMilestoneCount < _previousMilestoneCount || (!metrics.isRunning && metrics.history.isEmpty)) {
      _previousMilestoneCount = currentMilestoneCount;
    }

    final displaySpeed = isMetric
        ? metrics.speedKmh
        : metrics.speedKmh * 0.621371;

    double maxSpeed = isMetric ? 100.0 : 60.0;
    double speedRatio = (displaySpeed / maxSpeed).clamp(0.0, 1.0);

    Color speedColor;
    if (displaySpeed < 1.0) {
      speedColor = Colors.grey.shade800;
    } else if (displaySpeed > maxSpeed || metrics.gForce < 0) {
      speedColor = Colors.redAccent;
    } else {
      speedColor = const Color(0xFF39FF14);
    }

    double maxG = 1.0;
    double gRatio = (metrics.gForce.abs() / maxG).clamp(0.0, 1.0);

    Color gColor;
    if (metrics.gForce == 0.0) {
      gColor = Colors.grey.shade800;
    } else if (metrics.gForce < 0) {
      gColor = Colors.redAccent;
    } else {
      gColor = const Color(0xFF39FF14);
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black, // Background mimicking camera off state
      body: Stack(
        children: [
          // Background gradient to give it depth
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.grey.shade900, Colors.black],
              ),
            ),
          ),


          SafeArea(
            child: Column(
              children: [
                // Top flexible area that perfectly centers the text block
                // between the top of the screen and the bottom widgets
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        // Let taps pass through to the top-bar controls above.
                        const IgnorePointer(child: SizedBox(height: 72)),
                        const IgnorePointer(child: SizedBox(height: 12)),
                        // Dragy Logo Text
                          Text(
                            'OpenDragy',
                            style: GoogleFonts.comfortaa(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (dragy.activeVehicle != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFBF00,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFBF00,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.directions_car,
                                    color: Color(0xFFFFBF00),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dragy.activeVehicle!.displayName,
                                    style: GoogleFonts.roboto(
                                      color: const Color(0xFFFFBF00),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (!dragy.isLoggerMode &&
                              !metrics.isRunning &&
                              metrics.history.isEmpty) ...[
                            const SizedBox(height: 16),
                            // Mode Selector
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ModeButton(
                                    label: 'DRAG',
                                    isActive: dragy.runMode == 'drag',
                                    onTap: () => dragy.setRunMode('drag'),
                                  ),
                                  _ModeButton(
                                    label: 'INTERVAL',
                                    isActive: dragy.runMode == 'interval',
                                    onTap: () => dragy.setRunMode('interval'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Target Selector
                            if (dragy.runMode == 'drag')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.06),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<RaceDragTarget>(
                                    value: dragy.activeDragTarget,
                                    dropdownColor: Colors.grey.shade900,
                                    icon: const Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.white54,
                                    ),
                                    style: GoogleFonts.roboto(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    onChanged: (val) {
                                      if (val != null) {
                                        dragy.setActiveDragTarget(val);
                                      }
                                    },
                                    items: const [
                                      DropdownMenuItem(
                                        value: RaceDragTarget.sixtyFeet,
                                        child: Text('60 ft'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.threeHundredThirtyFeet,
                                        child: Text('330 ft'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.eighthMile,
                                        child: Text('1/8 mile'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.thousandFeet,
                                        child: Text('1000ft'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.quarterMile,
                                        child: Text('1/4 mile'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.halfMile,
                                        child: Text('1/2 mile'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.03),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.06),
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<RaceIntervalTarget>(
                                        value: dragy.activeIntervalTarget,
                                        dropdownColor: Colors.grey.shade900,
                                        icon: const Icon(
                                          Icons.arrow_drop_down,
                                          color: Colors.white54,
                                        ),
                                        style: GoogleFonts.roboto(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        onChanged: (val) {
                                          if (val != null) {
                                            dragy.setActiveIntervalTarget(val);
                                          }
                                        },
                                        items: dragy.isMetric
                                            ? const [
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToOneHundredKmh,
                                                  child: Text('0-100 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToOneSixtyKmh,
                                                  child: Text('0-160 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToTwoHundredKmh,
                                                  child: Text('0-200 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .eightyToOneTwentyKmh,
                                                  child: Text('80-120 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .oneHundredToOneSixtyKmh,
                                                  child: Text('100-160 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .oneHundredToTwoHundredKmh,
                                                  child: Text('100-200 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value:
                                                      RaceIntervalTarget.custom,
                                                  child: Text(
                                                    'Custom Range...',
                                                  ),
                                                ),
                                              ]
                                            : const [
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToSixtyMph,
                                                  child: Text('0-60 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToOneHundredMph,
                                                  child: Text('0-100 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .zeroToOneThirtyMph,
                                                  child: Text('0-130 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .fiftyToSeventyFiveMph,
                                                  child: Text('50-75 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .sixtyToOneHundredMph,
                                                  child: Text('60-100 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceIntervalTarget
                                                      .sixtyToOneThirtyMph,
                                                  child: Text('60-130 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value:
                                                      RaceIntervalTarget.custom,
                                                  child: Text(
                                                    'Custom Range...',
                                                  ),
                                                ),
                                              ],
                                      ),
                                    ),
                                  ),
                                  if (dragy.activeIntervalTarget ==
                                      RaceIntervalTarget.custom) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: () => _showCustomRangeDialog(
                                        context,
                                        dragy,
                                      ),
                                      icon: const Icon(
                                        Icons.edit_road,
                                        color: Color(0xFF42A5F5),
                                      ),
                                      tooltip: 'Edit Custom Range',
                                    ),
                                  ],
                                ],
                              ),
                            const SizedBox(height: 24),
                          ],
                          // Large Time/Status Display
                          SizedBox(
                            height: 110,
                            width: double.infinity,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: 0.95,
                                            end: 1.0,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      );
                                    },
                                child: Text(
                                  mainTime,
                                  key: ValueKey<String>(statusKey),
                                  style: GoogleFonts.robotoMono(
                                    color: textColor,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (dragy.isLoggerMode) ...[
                            const SizedBox(height: 16),
                            Text(
                              dragy.isRideRecording
                                  ? 'REC · ${dragy.rideTrackPointCount} GPS · '
                                      '${dragy.isConnected ? "live" : "reconnecting"}'
                                  : isConnected
                                      ? 'Set tags/notes, then Start'
                                      : 'Connect OpenDragy, then Start',
                              style: GoogleFonts.robotoMono(
                                color: dragy.isRideRecording
                                    ? Colors.redAccent
                                    : Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const GarageScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                dragy.activeVehicle != null
                                    ? 'Vehicle: ${dragy.activeVehicle!.displayName}'
                                    : 'Vehicle: none (tap to open Garage)',
                                style: GoogleFonts.roboto(
                                  color: const Color(0xFFFFBF00),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: LoggerTagsInput(
                                enabled: !dragy.isRideRecording,
                                tags: parseLoggerTags(dragy.loggerTagsText),
                                hintText: '98, Velocity Stack',
                                onTagsChanged: dragy.setLoggerTags,
                              ),
                            ),
                            if (dragy.loggerSuggestedTags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final tag in dragy.loggerSuggestedTags)
                                    ActionChip(
                                      label: Text(
                                        tag,
                                        style: GoogleFonts.roboto(fontSize: 12),
                                      ),
                                      backgroundColor: Colors.white10,
                                      side: const BorderSide(color: Colors.white24),
                                      onPressed: dragy.isRideRecording
                                          ? null
                                          : () => dragy.addLoggerTag(tag),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                enabled: !dragy.isRideRecording,
                                controller: _loggerNotesController,
                                onChanged: dragy.setLoggerNotes,
                                style: GoogleFonts.roboto(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Notes',
                                  labelStyle: GoogleFonts.roboto(
                                    color: Colors.white38,
                                  ),
                                  hintText: 'Optional session notes',
                                  hintStyle: GoogleFonts.roboto(
                                    color: Colors.white24,
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () async {
                                if (dragy.isRideRecording) {
                                  await dragy.stopRideRecording();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Logger stopped — session saved.',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final err = await dragy.startRideRecording();
                                if (context.mounted && err != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err)),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dragy.isRideRecording
                                    ? Colors.redAccent
                                    : const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 8,
                                shadowColor: dragy.isRideRecording
                                    ? Colors.redAccent.withOpacity(0.5)
                                    : const Color(0xFF1565C0).withOpacity(0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    dragy.isRideRecording
                                        ? Icons.stop
                                        : Icons.fiber_manual_record,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dragy.isRideRecording
                                        ? 'STOP REC'
                                        : 'START REC',
                                    style: GoogleFonts.roboto(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RideLogsScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Logger sessions',
                                style: GoogleFonts.roboto(color: Colors.white54),
                              ),
                            ),
                          ],
                          if (!dragy.isLoggerMode &&
                              isConnected &&
                              !(metrics.history.isNotEmpty &&
                                  !metrics.isRunning)) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => dragy.toggleArm(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dragy.isArmed
                                    ? Colors.redAccent
                                    : const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 8,
                                shadowColor: dragy.isArmed
                                    ? Colors.redAccent.withOpacity(0.5)
                                    : const Color(0xFF1565C0).withOpacity(0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    dragy.isArmed
                                        ? Icons.stop
                                        : Icons.play_arrow,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dragy.isArmed ? 'DISARM' : 'ARM',
                                    style: GoogleFonts.roboto(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (dragy.pocketMode &&
                                dragy.isArmed &&
                                !metrics.isRunning) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Pocket OK — screen may turn off',
                                style: GoogleFonts.roboto(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ],
                          if (metrics.history.isNotEmpty &&
                              !metrics.isRunning) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isSlopeValid
                                      ? Icons.check_circle_outline
                                      : Icons.warning_amber_outlined,
                                  size: 14,
                                  color: isSlopeValid
                                      ? const Color(0xFF39FF14)
                                      : Colors.redAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Overall Slope: ${avgSlope >= 0 ? '+' : ''}${avgSlope.toStringAsFixed(2)}% (${isSlopeValid ? "Valid" : "Invalid"})',
                                  style: GoogleFonts.roboto(
                                    color: isSlopeValid
                                        ? Colors.white70
                                        : Colors.redAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (reachedMilestones.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const Divider(color: Colors.white24, height: 1),
                            const SizedBox(height: 16),
                            Flexible(
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                child: Column(
                                  children: reachedMilestones.map((m) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: _ResultRow(
                                        label: m.label,
                                        time: m.time,
                                        trapSpeed: m.trapSpeed != null
                                            ? (isMetric
                                                  ? m.trapSpeed!
                                                  : m.trapSpeed! * 0.621371)
                                            : null,
                                        isMetric: isMetric,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ),

                // Bottom Elements
                if (isConnected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 35),
                    child: SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Speedometer
                          Positioned(
                            left: 15,
                            bottom: 0,
                            child: SizedBox(
                              width: 120,
                              height: 120,
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Grey Background Track
                                    Container(
                                      width: 110,
                                      height: 110,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade800,
                                        shape: BoxShape.circle,
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black45,
                                            blurRadius: 10,
                                            offset: Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Animated Color Fill
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 100,
                                      ),
                                      width: 70 + (speedRatio * 40.0),
                                      height: 70 + (speedRatio * 40.0),
                                      decoration: BoxDecoration(
                                        color: speedColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    // Black Center
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            displaySpeed.toStringAsFixed(0),
                                            style: GoogleFonts.robotoMono(
                                              color: Colors.white,
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0,
                                            ),
                                          ),
                                          Text(
                                            isMetric ? 'km/h' : 'mph',
                                            style: GoogleFonts.robotoMono(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // G-Force Meter
                          Align(
                            alignment: const Alignment(
                              -0.15,
                              1.0,
                            ), // Closer to speed
                            child: SizedBox(
                              width: 80,
                              height: 80,
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Grey Background Track
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade800,
                                        shape: BoxShape.circle,
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black45,
                                            blurRadius: 10,
                                            offset: Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Animated Color Fill
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 100,
                                      ),
                                      width: 46 + (gRatio * 24.0),
                                      height: 46 + (gRatio * 24.0),
                                      decoration: BoxDecoration(
                                        color: gColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    // Black Center
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            metrics.gForce
                                                .abs()
                                                .toStringAsFixed(1),
                                            style: GoogleFonts.robotoMono(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0,
                                            ),
                                          ),
                                          Text(
                                            'g',
                                            style: GoogleFonts.robotoMono(
                                              color: Colors.white70,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Reset Button
                          Positioned(
                            right: 15,
                            bottom: 0,
                            child: SizedBox(
                              width: 120,
                              height: 120,
                              child: Center(
                                child: InkWell(
                                  onTap: dragy.resetRace,
                                  borderRadius: BorderRadius.circular(60),
                                  child: Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade800,
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 10,
                                          offset: Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.refresh,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Top Bar (Signal Confidence and Connection)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 16.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Signal Confidence (Top Left) → satellite detail
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SatelliteStatusScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isConnected
                              ? Colors.amberAccent.withOpacity(0.1)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isConnected
                                ? Colors.amberAccent.withOpacity(0.5)
                                : Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.satellite_alt,
                                  color: isConnected
                                      ? Colors.amberAccent
                                      : Colors.white30,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isConnected
                                      ? '${dragy.satellites} SAT'
                                      : 'NO GPS',
                                  style: GoogleFonts.robotoMono(
                                    color: isConnected
                                        ? Colors.amberAccent
                                        : Colors.white30,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isConnected
                                  ? 'HDOP: ${dragy.hdop.toStringAsFixed(1)}'
                                  : 'Offline',
                              style: GoogleFonts.robotoMono(
                                color: isConnected
                                    ? Colors.amberAccent.withOpacity(0.8)
                                    : Colors.white24,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Action buttons (Garage, History, Settings & Connection)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Garage Button — in logger: first tap exits to drag UI
                      InkWell(
                        onTap: () async {
                          if (dragy.isLoggerMode) {
                            final wasRecording = dragy.isRideRecording;
                            await dragy.setLoggerMode(false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    wasRecording
                                        ? 'Drag mode — session saved. Tap car again for Garage.'
                                        : 'Drag mode — tap car again for Garage.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GarageScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: dragy.activeVehicle != null
                                ? const Color(0xFFFFBF00).withOpacity(0.12)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: dragy.activeVehicle != null
                                  ? const Color(0xFFFFBF00).withOpacity(0.5)
                                  : Colors.white24,
                            ),
                          ),
                          child: Icon(
                            Icons.directions_car_outlined,
                            color: dragy.activeVehicle != null
                                ? const Color(0xFFFFBF00)
                                : Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // History Button
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RunHistoryScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.history,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Logger toggle (long-press → sessions)
                      InkWell(
                        onTap: () async {
                          if (dragy.isLoggerMode) {
                            final wasRecording = dragy.isRideRecording;
                            await dragy.setLoggerMode(false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    wasRecording
                                        ? 'Logger off — session saved (GPX + CSV).'
                                        : 'Logger off.',
                                  ),
                                ),
                              );
                            }
                          } else {
                            if (!dragy.hasDurableDataFolder) {
                              await _ensureDurableFolder(context, dragy);
                            }
                            await dragy.setLoggerMode(true);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Logger on — set tags/notes, then Start Rec.',
                                  ),
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                          }
                        },
                        onLongPress: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RideLogsScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: dragy.isLoggerMode
                                ? Colors.redAccent.withOpacity(0.15)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: dragy.isLoggerMode
                                  ? Colors.redAccent.withOpacity(0.55)
                                  : Colors.white24,
                            ),
                          ),
                          child: Icon(
                            dragy.isLoggerMode
                                ? Icons.fiber_manual_record
                                : Icons.timeline,
                            color: dragy.isLoggerMode
                                ? Colors.redAccent
                                : Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Settings Button
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.settings_outlined,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Connection Button
                      InkWell(
                        onTap: () {
                          if (isConnected) {
                            if (dragy.isLoggerMode) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Turn off Logger before disconnecting.',
                                  ),
                                ),
                              );
                              return;
                            }
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: Colors.grey.shade900,
                                title: const Text(
                                  'Disconnect',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: Text(
                                  'Disconnect from ${dragy.connectedDevice?.platformName ?? "device"}?',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      dragy.disconnect();
                                      Navigator.pop(context);
                                    },
                                    child: const Text(
                                      'Disconnect',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            _showDeviceSelector(context);
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? Colors.greenAccent.withOpacity(0.12)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isConnected
                                  ? Colors.greenAccent.withOpacity(0.5)
                                  : Colors.white24,
                            ),
                          ),
                          child: Icon(
                            isConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            color: isConnected
                                ? Colors.greenAccent
                                : Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (dragy.finishCelebrationToken > 0 &&
              dragy.finishCelebration != FinishCelebrationMode.off)
            FinishCelebrationOverlay(
              key: ValueKey(dragy.finishCelebrationToken),
              mode: dragy.finishCelebration,
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final double? time;
  final double? trapSpeed;
  final bool isMetric;

  const _ResultRow({
    required this.label,
    this.time,
    this.trapSpeed,
    required this.isMetric,
  });

  @override
  Widget build(BuildContext context) {
    final isFinished = time != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Green Dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isFinished ? Colors.greenAccent : Colors.grey.shade800,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 16),
        // Label
        Text(
          label,
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        // Result
        Text(
          isFinished
              ? (trapSpeed != null
                    ? '${time!.toStringAsFixed(2)}s@${trapSpeed!.toStringAsFixed(2)}'
                    : '${time!.toStringAsFixed(2)}s')
              : '-.--s',
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1565C0) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.roboto(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

void _showCustomRangeDialog(BuildContext context, DragyProvider dragy) {
  final isMetric = dragy.isMetric;
  final startController = TextEditingController(
    text: dragy.customIntervalStartSpeedUserUnit.toStringAsFixed(0),
  );
  final endController = TextEditingController(
    text: dragy.customIntervalEndSpeedUserUnit.toStringAsFixed(0),
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: Text(
        'Custom Speed Range (${isMetric ? 'km/h' : 'mph'})',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: startController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Start Speed',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: endController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'End Speed',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () {
            final start = double.tryParse(startController.text) ?? 100.0;
            final end = double.tryParse(endController.text) ?? 200.0;
            dragy.setCustomIntervalRange(start, end);
            Navigator.pop(context);
          },
          child: const Text(
            'Save',
            style: TextStyle(color: Colors.greenAccent),
          ),
        ),
      ],
    ),
  );
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import '../widgets/device_selector_modal.dart';
import 'run_history_screen.dart';
import 'garage_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
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
    final metrics = dragy.metrics;
    final isConnected = dragy.isConnected;
    final isMetric = dragy.isMetric;

    // Determine the main highlighted time or status message
    String mainTime = "0.00s";
    double fontSize = 80.0;
    Color textColor = Colors.white;
    String statusKey = "ready";

    if (!isConnected) {
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
      if (dragy.runMode == 'rolling') {
        switch (dragy.activeRollingTarget) {
          case RaceRollingTarget.sixtyToOneThirtyMph:
            completedTime = metrics.time60to130mph;
            break;
          case RaceRollingTarget.oneHundredToTwoHundredKmh:
            completedTime = metrics.time100to200kmh;
            break;
          case RaceRollingTarget.zeroToSixtyMph:
            completedTime = metrics.time0to60mph;
            break;
          case RaceRollingTarget.zeroToOneHundredKmh:
            completedTime = metrics.time0to100kmh;
            break;
          case RaceRollingTarget.fiftyToSeventyFiveMph:
          case RaceRollingTarget.eightyToOneTwentyKmh:
          case RaceRollingTarget.custom:
            completedTime = metrics.elapsedTime > 0
                ? metrics.elapsedTime
                : null;
            break;
        }
      } else {
        if (metrics.time12Mile != null) {
          completedTime = metrics.time12Mile;
        } else if (metrics.time14Mile != null) {
          completedTime = metrics.time14Mile;
        } else if (metrics.time1000ft != null) {
          completedTime = metrics.time1000ft;
        } else if (metrics.time18Mile != null) {
          completedTime = metrics.time18Mile;
        } else if (metrics.time0to60mph != null ||
            metrics.time0to100kmh != null) {
          if (isMetric && metrics.time0to100kmh != null) {
            completedTime = metrics.time0to100kmh;
          } else if (!isMetric && metrics.time0to60mph != null) {
            completedTime = metrics.time0to60mph;
          } else if (metrics.time0to100kmh != null) {
            completedTime = metrics.time0to100kmh;
          } else if (metrics.time0to60mph != null) {
            completedTime = metrics.time0to60mph;
          }
        } else if (metrics.time60ft != null) {
          completedTime = metrics.time60ft;
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
      if (metrics.time60ft != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: '60ft',
            time: metrics.time60ft!,
            sortTime: metrics.time60ft!,
          ),
        );
      }

      final double? tSpeedUnit = isMetric
          ? metrics.time0to100kmh
          : metrics.time0to60mph;
      if (tSpeedUnit != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: isMetric ? '0-100km/h' : '0-60mph',
            time: tSpeedUnit,
            sortTime: tSpeedUnit,
          ),
        );
      }

      if (metrics.time18Mile != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: '1/8mile',
            time: metrics.time18Mile!,
            sortTime: metrics.time18Mile!,
            trapSpeed: metrics.trap18Mile,
          ),
        );
      }
      if (metrics.time1000ft != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: '1000ft',
            time: metrics.time1000ft!,
            sortTime: metrics.time1000ft!,
            trapSpeed: metrics.trap1000ft,
          ),
        );
      }
      if (metrics.time14Mile != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: '1/4mile',
            time: metrics.time14Mile!,
            sortTime: metrics.time14Mile!,
            trapSpeed: metrics.trap14Mile,
          ),
        );
      }
      if (metrics.time12Mile != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: '1/2mile',
            time: metrics.time12Mile!,
            sortTime: metrics.time12Mile!,
            trapSpeed: metrics.trap12Mile,
          ),
        );
      }

      final double? tInterval = isMetric
          ? metrics.time100to200kmh
          : metrics.time60to130mph;
      if (tInterval != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: isMetric ? '100-200km/h' : '60-130mph',
            time: tInterval,
            sortTime: isMetric
                ? (metrics.time0to100kmh ?? 0.0) + tInterval
                : (metrics.time0to60mph ?? 0.0) + tInterval,
          ),
        );
      }

      final double? t0to130_200 = isMetric
          ? metrics.time0to200kmh
          : metrics.time0to130mph;
      if (t0to130_200 != null) {
        reachedMilestones.add(
          _ReachedMilestone(
            label: isMetric ? '0-200km/h' : '0-130mph',
            time: t0to130_200,
            sortTime: t0to130_200,
          ),
        );
      }
    } else {
      switch (dragy.activeRollingTarget) {
        case RaceRollingTarget.sixtyToOneThirtyMph:
          if (metrics.time60to130mph != null) {
            reachedMilestones.add(
              _ReachedMilestone(
                label: '60-130 mph',
                time: metrics.time60to130mph!,
                sortTime: metrics.time60to130mph!,
              ),
            );
          }
          break;
        case RaceRollingTarget.oneHundredToTwoHundredKmh:
          if (metrics.time100to200kmh != null) {
            reachedMilestones.add(
              _ReachedMilestone(
                label: '100-200 km/h',
                time: metrics.time100to200kmh!,
                sortTime: metrics.time100to200kmh!,
              ),
            );
          }
          break;
        case RaceRollingTarget.zeroToSixtyMph:
          if (metrics.time0to60mph != null) {
            reachedMilestones.add(
              _ReachedMilestone(
                label: '0-60 mph',
                time: metrics.time0to60mph!,
                sortTime: metrics.time0to60mph!,
              ),
            );
          }
          break;
        case RaceRollingTarget.zeroToOneHundredKmh:
          if (metrics.time0to100kmh != null) {
            reachedMilestones.add(
              _ReachedMilestone(
                label: '0-100 km/h',
                time: metrics.time0to100kmh!,
                sortTime: metrics.time0to100kmh!,
              ),
            );
          }
          break;
        case RaceRollingTarget.fiftyToSeventyFiveMph:
        case RaceRollingTarget.eightyToOneTwentyKmh:
        case RaceRollingTarget.custom:
          if (!metrics.isRunning &&
              metrics.history.isNotEmpty &&
              metrics.elapsedTime > 0) {
            reachedMilestones.add(
              _ReachedMilestone(
                label: dragy.activeRollingTargetLabel,
                time: metrics.elapsedTime,
                sortTime: metrics.elapsedTime,
              ),
            );
          }
          break;
      }
    }

    reachedMilestones.sort((a, b) => a.sortTime.compareTo(b.sortTime));

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
                  // Signal Confidence (Top Left)
                  Container(
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

                  // Action buttons (Garage, History, Settings & Connection)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Garage Button
                      InkWell(
                        onTap: () {
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

          SafeArea(
            child: Column(
              children: [
                // Top flexible area that perfectly centers the text block
                // between the top of the screen and the bottom widgets
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
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
                          if (!metrics.isRunning &&
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
                                    isActive: dragy.runMode == 'rolling',
                                    onTap: () => dragy.setRunMode('rolling'),
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
                                      if (val != null)
                                        dragy.setActiveDragTarget(val);
                                    },
                                    items: const [
                                      DropdownMenuItem(
                                        value: RaceDragTarget.sixtyFeet,
                                        child: Text('60 ft'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.eighthMile,
                                        child: Text('1/8 mile'),
                                      ),
                                      DropdownMenuItem(
                                        value: RaceDragTarget.thousandFeet,
                                        child: Text('1000 ft'),
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
                                      child: DropdownButton<RaceRollingTarget>(
                                        value: dragy.activeRollingTarget,
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
                                          if (val != null)
                                            dragy.setActiveRollingTarget(val);
                                        },
                                        items: dragy.isMetric
                                            ? const [
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .zeroToOneHundredKmh,
                                                  child: Text('0-100 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .eightyToOneTwentyKmh,
                                                  child: Text('80-120 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .oneHundredToTwoHundredKmh,
                                                  child: Text('100-200 km/h'),
                                                ),
                                                DropdownMenuItem(
                                                  value:
                                                      RaceRollingTarget.custom,
                                                  child: Text(
                                                    'Custom Range...',
                                                  ),
                                                ),
                                              ]
                                            : const [
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .zeroToSixtyMph,
                                                  child: Text('0-60 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .fiftyToSeventyFiveMph,
                                                  child: Text('50-75 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value: RaceRollingTarget
                                                      .sixtyToOneThirtyMph,
                                                  child: Text('60-130 mph'),
                                                ),
                                                DropdownMenuItem(
                                                  value:
                                                      RaceRollingTarget.custom,
                                                  child: Text(
                                                    'Custom Range...',
                                                  ),
                                                ),
                                              ],
                                      ),
                                    ),
                                  ),
                                  if (dragy.activeRollingTarget ==
                                      RaceRollingTarget.custom) ...[
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
                          if (isConnected &&
                              !(metrics.history.isNotEmpty &&
                                  !metrics.isRunning)) ...[
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: dragy.toggleArm,
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
                          const SizedBox(height: 24),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 16),
                          Column(
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
                        ],
                      ),
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
                    ? '${time!.toStringAsFixed(2)}s@${trapSpeed!.toStringAsFixed(1)} ${isMetric ? "km/h" : "mph"}'
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
    text: dragy.customRollingStartSpeedUserUnit.toStringAsFixed(0),
  );
  final endController = TextEditingController(
    text: dragy.customRollingEndSpeedUserUnit.toStringAsFixed(0),
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
            dragy.setCustomRollingRange(start, end);
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

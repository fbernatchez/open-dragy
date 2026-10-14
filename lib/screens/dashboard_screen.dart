import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../providers/telemetry_provider.dart';
import '../widgets/device_selector_modal.dart';
import '../widgets/firmware_update_dialog.dart';
import '../widgets/app_segmented_switch.dart';
import '../services/firmware_service.dart';
import 'garage_screen.dart';
import '../utils/unit_converter.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  int _previousMilestoneCount = 0;
  bool _hasPromptedUpdate = false;
  bool _pendingUpdatePrompt = false;
  DragyProvider? _dragyProviderRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dragyProviderRef = Provider.of<DragyProvider>(context, listen: false);
      _dragyProviderRef?.addListener(_onProviderChange);
    });
  }

  @override
  void dispose() {
    _dragyProviderRef?.removeListener(_onProviderChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderChange() {
    if (!mounted || _dragyProviderRef == null) return;

    if (!_dragyProviderRef!.isConnected) {
      _hasPromptedUpdate = false;
      _pendingUpdatePrompt = false;
      return;
    }

    if (_dragyProviderRef!.isConnected &&
        _dragyProviderRef!.firmwareVersion.isNotEmpty &&
        !_hasPromptedUpdate) {
      if (FirmwareService.isUpdateAvailable(_dragyProviderRef!.firmwareVersion)) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          _hasPromptedUpdate = true;
          _showUpdatePromptDialog();
        } else {
          _pendingUpdatePrompt = true;
        }
      }
    }
  }

  void _showUpdatePromptDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const FirmwareUpdateDialog(),
    );
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
    ).then((_) {
      if (!mounted) return;
      if (_pendingUpdatePrompt) {
        _pendingUpdatePrompt = false;
        _hasPromptedUpdate = true;
        _showUpdatePromptDialog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final telemetry = Provider.of<TelemetryProvider?>(context);
    final isMetric = dragy.isMetric;
    final isConnected = dragy.isConnected;
    final metrics = telemetry?.metrics ?? dragy.metrics;
    final liveElapsedTime = telemetry?.liveElapsedTime ?? dragy.liveElapsedTime;
    final isArmed = telemetry?.isArmed ?? dragy.isArmed;
    final hdop = telemetry?.hdop ?? dragy.hdop;
    final onToggleArm = telemetry != null ? telemetry.toggleArm : dragy.toggleArm;
    final onResetRace = telemetry != null ? telemetry.resetRace : dragy.resetRace;

    final colors = context.colors;
    final isDark = context.isDark;
    final primaryTextColor = colors.textPrimary;
    final secondaryTextColor = colors.textSecondary;
    final mutedTextColor = colors.textMuted;
    final surfaceCardColor = colors.subtleBackground;
    final surfaceBorderColor = colors.cardBorder;

    // Determine the main highlighted time or status message
    String mainTime = "0.00s";
    double fontSize = 80.0;
    Color textColor = primaryTextColor;
    String statusKey = "ready";
    const double statusFontSize = 52.0;
    bool shouldBlink = false;

    IconData? statusIcon;
    Color? statusIconColor;
    String? statusSubtitle;

    if (!isConnected) {
      mainTime = "Disconnected";
      fontSize = statusFontSize;
      textColor = mutedTextColor;
      statusKey = "disconnected";
    } else if (metrics.isRunning) {
      mainTime = "${liveElapsedTime.toStringAsFixed(2)}s";
      fontSize = 80.0;
      textColor = primaryTextColor;
      statusKey = "running";
    } else {
      double? completedTime;
      if (dragy.runMode == RunMode.interval) {
        String intervalId = dragy.activeIntervalTest.id;
        if (dragy.activeIntervalTest == RaceIntervalTest.custom) {
          final unit = isMetric ? 'kmh' : 'mph';
          intervalId =
              'custom_${dragy.customIntervalStartSpeed.round()}_${dragy.customIntervalEndSpeed.round()}_$unit';
        }
        completedTime = getCompletedTimeForCategory(
          metrics,
          intervalId,
          useNhraRules: dragy.useNhraRules,
        );
      } else {
        final activeTestsList = [...officialTests, ...dragy.customTests];
        final completed = getCompletedTests(
          metrics,
          useNhraRules: dragy.useNhraRules,
          activeTests: activeTestsList,
        );
        double maxTime = -1.0;
        for (final test in completed) {
          if (!test.matchesUnitSystem(isMetric)) {
            continue;
          }
          final t = getCompletedTimeForCategory(
            metrics,
            test.id,
            useNhraRules: dragy.useNhraRules,
            activeTests: activeTestsList,
          );
          if (t != null && t > maxTime) {
            maxTime = t;
            completedTime = t;
          }
        }
      }

      if (completedTime != null) {
        mainTime = "${completedTime.toStringAsFixed(2)}s";
        fontSize = 80.0;
        textColor = primaryTextColor;
        statusKey = "finished";
      } else {
        final bool isGpsReady = hdop > 0.0 && hdop <= 2.0;
        final warningColor = colors.statusWarning;
        final warningIconColor = isDark
            ? colors.statusWarning.withValues(alpha: 0.7)
            : colors.statusWarning;

        if (!isGpsReady) {
          mainTime = "Waiting for GPS";
          fontSize = statusFontSize;
          textColor = warningColor;
          statusKey = "waiting_gps";
          statusIcon = Icons.satellite_alt_rounded;
          statusIconColor = warningIconColor;
          statusSubtitle = "Acquiring satellite lock";
        } else if (isArmed) {
          final bool isStandingStart = dragy.runMode == RunMode.drag ||
              (dragy.runMode == RunMode.interval &&
                  dragy.intervalStartSpeed == 0.0);
          if (isStandingStart) {
            if (metrics.speedKmh > 0.0) {
              mainTime = "STOP";
              fontSize = statusFontSize;
              textColor = colors.statusDanger;
              statusKey = "stop";
              shouldBlink = true;
              statusIcon = Icons.front_hand_rounded;
              statusIconColor = colors.statusDanger.withValues(alpha: 0.9);
              statusSubtitle = "Bring vehicle to a complete stop";
            } else {
              mainTime = "Ready to Launch";
              fontSize = statusFontSize;
              textColor = primaryTextColor;
              statusKey = "armed";
              statusIcon = Icons.sports_score_rounded;
              statusIconColor = colors.accentSecondary.withValues(alpha: isDark ? 0.7 : 0.9);
              statusSubtitle = "Launch whenever ready";
            }
          } else {
            // Rolling Interval Mode
            final double startSpeed = dragy.intervalStartSpeed;
            final double endSpeed = dragy.intervalEndSpeed;
            final bool isBraking = startSpeed > endSpeed;

            if (!isBraking && metrics.speedKmh > startSpeed) {
              mainTime = "Slow Down";
              fontSize = statusFontSize;
              textColor = warningColor;
              statusKey = "slow_down";
              statusIcon = Icons.arrow_downward_rounded;
              statusIconColor = warningIconColor;
              statusSubtitle = "Current speed is above target entry speed";
            } else if (isBraking && metrics.speedKmh < startSpeed) {
              mainTime = "Speed Up";
              fontSize = statusFontSize;
              textColor = warningColor;
              statusKey = "speed_up";
              statusIcon = Icons.arrow_upward_rounded;
              statusIconColor = warningIconColor;
              statusSubtitle = "Accelerate to reach target entry speed";
            } else {
              mainTime = isBraking ? "Ready to Brake" : "Ready to Run";
              fontSize = statusFontSize;
              textColor = primaryTextColor;
              statusKey = "armed";
              statusIcon = Icons.speed_rounded;
              statusIconColor = colors.accentSecondary.withValues(alpha: isDark ? 0.7 : 0.9);
              statusSubtitle = isBraking
                  ? "Apply brakes to begin test"
                  : "Accelerate to start test";
            }
          }
        } else {
          mainTime = "Disarmed";
          fontSize = statusFontSize;
          textColor = mutedTextColor;
          statusKey = "disarmed";
          statusIcon = Icons.shield_outlined;
          statusIconColor = colors.textMuted.withValues(alpha: isDark ? 0.35 : 0.6);
          statusSubtitle = "Tap ARM when ready";
        }
      }
    }

    final double avgSlope = metrics.avgSlope;
    final bool isSlopeValid = metrics.isSlopeValid;

    // Collect reached milestones sorted by completion time ascending
    final reachedMilestones = getReachedMilestones(
      metrics,
      isMetric: isMetric,
      useNhraRules: dragy.useNhraRules,
      customTests: dragy.customTests,
      isTestEnabled: dragy.isTestEnabled,
      includeTrapSpeed: dragy.runMode == RunMode.drag,
    );

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
    } else if (currentMilestoneCount < _previousMilestoneCount ||
        (!metrics.isRunning && metrics.history.isEmpty)) {
      _previousMilestoneCount = currentMilestoneCount;
    }

    final displaySpeed = isMetric
        ? metrics.speedKmh
        : UnitConverter.kmhToMph(metrics.speedKmh);

    double maxSpeed = isMetric ? 100.0 : 60.0;
    double speedRatio = (displaySpeed / maxSpeed).clamp(0.0, 1.0);

    Color speedColor;
    if (displaySpeed < 1.0) {
      speedColor = colors.instrumentRing;
    } else if (displaySpeed > maxSpeed || metrics.gForce < 0) {
      speedColor = Colors.redAccent;
    } else {
      speedColor = colors.accentSecondary;
    }

    double maxG = 1.0;
    double gRatio = (metrics.gForce.abs() / maxG).clamp(0.0, 1.0);

    Color gColor;
    if (metrics.gForce == 0.0) {
      gColor = colors.instrumentRing;
    } else if (metrics.gForce < 0) {
      gColor = Colors.redAccent;
    } else {
      gColor = colors.accentSecondary;
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.satellite_alt_rounded),
          color: isConnected ? primaryTextColor : mutedTextColor,
          tooltip: 'GPS Telemetry',
          onPressed: () => _showGpsStatusModal(context),
        ),
        title: const Text('OpenDragy'),
        actions: [
          IconButton(
            onPressed: () {
              if (isConnected) {
                _showDisconnectDialog(context, dragy);
              } else {
                _showDeviceSelector(context);
              }
            },
            tooltip: isConnected ? 'Disconnect' : 'Connect',
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected
                  ? colors.accentSecondary
                  : mutedTextColor,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background subtle gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors.dashboardGradient,
              ),
            ),
          ),

          SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [

                const SizedBox(height: 6),
                const _LiveWeatherWidget(),
                const SizedBox(height: 8),

                // 2. Active Vehicle Pill
                GestureDetector(
                  onTap: () => _showVehicleSelectorSheet(context, dragy),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: dragy.activeVehicle != null
                          ? colors.accent.withOpacity(isDark ? 0.08 : 0.12)
                          : colors.subtleBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: dragy.activeVehicle != null
                            ? colors.accent.withOpacity(0.35)
                            : surfaceBorderColor,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.directions_car,
                          color: dragy.activeVehicle != null
                              ? colors.accent
                              : mutedTextColor,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dragy.activeVehicle?.displayName ?? 'Select Vehicle',
                          style: AppTheme.font(
                            color: dragy.activeVehicle != null
                                ? colors.accent
                                : secondaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Mode & Target Selectors (Hidden during running run or while viewing finished run)
                if (!metrics.isRunning && metrics.history.isEmpty) ...[
                  const SizedBox(height: 10),
                  // Mode Selector
                  AppSegmentedSwitch<RunMode>(
                    selectedValue: dragy.runMode,
                    items: const [
                      SegmentedSwitchItem(
                        value: RunMode.drag,
                        label: 'DRAG',
                      ),
                      SegmentedSwitchItem(
                        value: RunMode.interval,
                        label: 'INTERVAL',
                      ),
                    ],
                    onChanged: (mode) => dragy.setRunMode(mode),
                  ),
                  const SizedBox(height: 10),
                  // Target Test Dropdown Pill
                  if (dragy.runMode == RunMode.drag)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: surfaceCardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: surfaceBorderColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<RaceDragTest>(
                          isDense: true,
                          value: dragy.activeDragTest,
                          dropdownColor: surfaceCardColor,
                          icon: Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Icon(
                              Icons.expand_more,
                              color: mutedTextColor,
                              size: 18,
                            ),
                          ),
                          style: AppTheme.font(
                            color: primaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              dragy.setActiveDragTest(val);
                            }
                          },
                          items: RaceDragTest.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    )
                  else
                    IntrinsicHeight(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: surfaceCardColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: surfaceBorderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<RaceIntervalTest>(
                                key: const Key('intervalTestDropdown'),
                                isDense: true,
                                value: dragy.activeIntervalTest,
                                dropdownColor: surfaceCardColor,
                                icon: Padding(
                                  padding: const EdgeInsets.only(left: 6.0),
                                  child: Icon(
                                    Icons.expand_more,
                                    color: mutedTextColor,
                                    size: 18,
                                  ),
                                ),
                                style: AppTheme.font(
                                  color: primaryTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                onChanged: (val) {
                                  if (val != null) {
                                    dragy.setactiveIntervalTest(val);
                                  }
                                },
                                items: RaceIntervalTest.values
                                    .where(
                                      (t) =>
                                          t == RaceIntervalTest.custom ||
                                          (dragy.isMetric
                                              ? t.id.contains('kmh')
                                              : t.id.contains('mph')),
                                    )
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.label),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                          if (dragy.activeIntervalTest ==
                              RaceIntervalTest.custom) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () =>
                                  _showCustomRangeDialog(context, dragy),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: surfaceCardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: surfaceBorderColor),
                                ),
                                child: const Icon(
                                  Icons.edit_road,
                                  color: Color(0xFF42A5F5),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],

                // 4. Center Content (Disconnected Graphic OR Active Race HUD)
                Expanded(
                  child: !isConnected
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const SizedBox(height: 48),
                              Icon(
                                Icons.link_off_rounded,
                                size: 84,
                                color: mutedTextColor,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Disconnected',
                                style: AppTheme.font(
                                  color: primaryTextColor,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the Bluetooth icon to connect',
                                style: AppTheme.font(
                                  color: mutedTextColor,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              // Large Time / Status Display
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) {
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
                                child: statusIcon != null
                                    ? Column(
                                        key: ValueKey<String>(statusKey),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _BlinkingWidget(
                                            isBlinking: shouldBlink,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 12),
                                                Icon(
                                                  statusIcon,
                                                  size: 64,
                                                  color: statusIconColor,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  mainTime,
                                                  style: AppTheme.font(
                                                    color: textColor,
                                                    fontSize: 30,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: -0.5,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (statusSubtitle != null) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              statusSubtitle,
                                              style: AppTheme.font(
                                                color: secondaryTextColor,
                                                fontSize: 13,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ],
                                      )
                                    : SizedBox(
                                        key: ValueKey<String>(statusKey),
                                        height: 100,
                                        width: double.infinity,
                                        child: Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16.0,
                                              ),
                                              child: _BlinkingWidget(
                                                isBlinking: shouldBlink,
                                                child: Text(
                                                  mainTime,
                                                  style: AppTheme.numericFont(
                                                    color: textColor,
                                                    fontSize: fontSize,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              if (!(metrics.history.isNotEmpty &&
                                  !metrics.isRunning)) ...[
                                SizedBox(height: statusIcon != null ? 24 : 16),
                                ElevatedButton(
                                  onPressed: onToggleArm,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isArmed
                                        ? Colors.redAccent
                                        : const Color(0xFF1565C0),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 40,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 8,
                                    shadowColor: isArmed
                                        ? Colors.redAccent.withOpacity(0.5)
                                        : const Color(0xFF1565C0)
                                            .withOpacity(0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isArmed
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isArmed ? 'DISARM' : 'ARM',
                                        style: AppTheme.font(
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
                                          ? colors.accentSecondary
                                          : Colors.redAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Overall Slope: ${avgSlope >= 0 ? '+' : ''}${avgSlope.toStringAsFixed(2)}% (${isSlopeValid ? "Valid" : "Invalid"})',
                                      style: AppTheme.font(
                                        color: isSlopeValid
                                            ? secondaryTextColor
                                            : Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (reachedMilestones.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Divider(color: surfaceBorderColor, height: 1),
                                const SizedBox(height: 12),
                                Flexible(
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    child: Column(
                                      children: reachedMilestones.map((m) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12.0,
                                          ),
                                          child: _ResultRow(
                                            label: m.label,
                                            time: m.time,
                                            trapSpeed: m.trapSpeed != null
                                                ? (isMetric
                                                    ? m.trapSpeed!
                                                    : UnitConverter.kmhToMph(
                                                        m.trapSpeed!,
                                                      ))
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

                // 5. Bottom Instrument Cluster (Speedometer, G-Force, Reset)
                if (isConnected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
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
                                    Container(
                                      width: 110,
                                      height: 110,
                                      decoration: BoxDecoration(
                                        color: colors.instrumentRing,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: isDark
                                                ? Colors.black45
                                                : Colors.black12,
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                    ),
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
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        color: colors.instrumentFace,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            displaySpeed.toStringAsFixed(0),
                                            style: AppTheme.numericFont(
                                              color: primaryTextColor,
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0,
                                            ),
                                          ),
                                          Text(
                                            isMetric ? 'km/h' : 'mph',
                                            style: AppTheme.font(
                                              color: secondaryTextColor,
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
                            alignment: const Alignment(-0.15, 1.0),
                            child: SizedBox(
                              width: 80,
                              height: 80,
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        color: colors.instrumentRing,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: isDark
                                                ? Colors.black45
                                                : Colors.black12,
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                    ),
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
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: colors.instrumentFace,
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
                                            style: AppTheme.numericFont(
                                              color: primaryTextColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              height: 1.0,
                                            ),
                                          ),
                                          Text(
                                            'g',
                                            style: AppTheme.font(
                                              color: secondaryTextColor,
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
                                  onTap: onResetRace,
                                  borderRadius: BorderRadius.circular(60),
                                  child: Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      color: colors.instrumentRing,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: isDark
                                              ? Colors.black45
                                              : Colors.black12,
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.refresh,
                                        color: primaryTextColor,
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

  void _showGpsStatusModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Consumer2<DragyProvider, TelemetryProvider?>(
          builder: (context, dragy, telemetry, _) {
            final colors = context.colors;
            final bool isConnected = dragy.isConnected;
            final double hdop = telemetry?.hdop ?? dragy.hdop;
            final int satellites = telemetry?.satellites ?? dragy.satellites;
            final bool isGpsReady =
                isConnected && hdop > 0.0 && hdop <= 2.0;

            String statusTitle;
            String statusSubtitle;
            Color statusColor;
            IconData statusIcon;

            if (!isConnected) {
              statusTitle = 'OpenDragy Disconnected';
              statusSubtitle =
                  'Connect your OpenDragy device to receive live GPS telemetry.';
              statusColor = colors.textMuted;
              statusIcon = Icons.link_off_rounded;
            } else if (isGpsReady) {
              statusTitle = 'GPS Locked';
              statusSubtitle =
                  'High-precision GNSS fix ready for performance timing.';
              statusColor = colors.accentSecondary;
              statusIcon = Icons.check_circle_rounded;
            } else {
              statusTitle = satellites > 0
                  ? 'Acquiring Satellites'
                  : 'Searching GPS';
              statusSubtitle =
                  'Waiting for optimal constellation geometry (HDOP <= 2.0).';
              statusColor = const Color(0xFFFFB300);
              statusIcon = Icons.sync_rounded;
            }

            return Container(
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: colors.cardBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.modalHandle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.satellite_alt_rounded,
                              color: colors.textPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'GPS Telemetry',
                              style: AppTheme.font(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: colors.textMuted, size: 20),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Status banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: statusColor.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  statusTitle,
                                  style: AppTheme.font(
                                    color: statusColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  statusSubtitle,
                                  style: AppTheme.font(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Metric cards
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.subtleBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.subtleBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SATELLITES',
                                    style: AppTheme.font(
                                      color: colors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isConnected ? '$satellites' : '--',
                                    style: AppTheme.numericFont(
                                      color: colors.textPrimary,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.subtleBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.subtleBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ACCURACY (HDOP)',
                                    style: AppTheme.font(
                                      color: colors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isConnected && hdop > 0
                                        ? hdop.toStringAsFixed(1)
                                        : '--',
                                    style: AppTheme.numericFont(
                                      color: colors.textPrimary,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Dragy hardware note
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.subtleBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: colors.textMuted, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'OpenDragy requires HDOP <= 2.0.',
                              style: AppTheme.font(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDisconnectDialog(BuildContext context, DragyProvider dragy) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Disconnect',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Disconnect from ${dragy.connectedDevice?.platformName ?? "device"}?',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              dragy.disconnect();
              Navigator.pop(context);
            },
            child: Text(
              'Disconnect',
              style: TextStyle(color: colors.statusDanger),
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleSelectorSheet(BuildContext context, DragyProvider dragy) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final colors = context.colors;
        final vehicles = dragy.vehicles;
        return Container(
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.modalHandle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Vehicle',
                    style: AppTheme.font(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GarageScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Manage Garage',
                      style: AppTheme.font(
                        color: colors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (vehicles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.directions_car_outlined,
                          size: 48,
                          color: colors.textMuted,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No vehicles in garage yet',
                          style: AppTheme.font(color: colors.textMuted),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.buttonForeground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const GarageScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Vehicle'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: vehicles.length,
                    itemBuilder: (context, index) {
                      final v = vehicles[index];
                      final isSelected = v.id == dragy.activeVehicleId;
                      return InkWell(
                        onTap: () {
                          dragy.setActiveVehicle(v.id);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.accent.withOpacity(0.12)
                                : colors.subtleBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? colors.accent.withOpacity(0.5)
                                  : colors.subtleBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.directions_car,
                                color: isSelected
                                    ? colors.accent
                                    : colors.textMuted,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  v.displayName,
                                  style: AppTheme.font(
                                    color: isSelected
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: colors.accent,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
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
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Green Dot
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isFinished ? colors.accentSecondary : colors.instrumentRing,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 16),
        // Label
        Text(
          label,
          style: AppTheme.font(
            color: colors.textPrimary,
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
          style: AppTheme.numericFont(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}



void _showCustomRangeDialog(BuildContext context, DragyProvider dragy) {
  final isMetric = dragy.isMetric;
  final colors = context.colors;
  final startController = TextEditingController(
    text: dragy.customIntervalStartSpeedUserUnit.toStringAsFixed(0),
  );
  final endController = TextEditingController(
    text: dragy.customIntervalEndSpeedUserUnit.toStringAsFixed(0),
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Custom Speed Range (${isMetric ? 'km/h' : 'mph'})',
        style: TextStyle(color: colors.textPrimary),
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
            decoration: InputDecoration(
              labelText: 'Start Speed',
              labelStyle: TextStyle(color: colors.textMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.subtleBorder),
              ),
            ),
            style: TextStyle(color: colors.textPrimary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: endController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'End Speed',
              labelStyle: TextStyle(color: colors.textMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.subtleBorder),
              ),
            ),
            style: TextStyle(color: colors.textPrimary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () {
            final start = double.tryParse(startController.text) ?? 100.0;
            final end = double.tryParse(endController.text) ?? 200.0;
            dragy.setCustomIntervalRange(start, end);
            Navigator.pop(context);
          },
          child: Text(
            'Save',
            style: TextStyle(color: colors.accentSecondary),
          ),
        ),
      ],
    ),
  );
}

class _LiveWeatherWidget extends StatelessWidget {
  const _LiveWeatherWidget();

  @override
  Widget build(BuildContext context) {
    final dragy = context.watch<DragyProvider>();
    final tempC = dragy.currentTemperature;

    if (tempC == null) {
      return const SizedBox(height: 28);
    }

    final unit = dragy.tempInCelsius ? '°C' : '°F';

    final temp = dragy.tempInCelsius
        ? tempC
        : UnitConverter.celsiusToFahrenheit(tempC);
    final tempStr = '${temp.toStringAsFixed(1)}$unit';

    final isaTemp = 15.0 - 0.0065 * dragy.altitude;
    final daMeters = dragy.altitude + 120.0 * (tempC - isaTemp);
    final daStr = dragy.isMetric
        ? '${daMeters.toStringAsFixed(0)} m'
        : '${UnitConverter.metersToFeet(daMeters).toStringAsFixed(0)} ft';

    final humidityStr = dragy.currentHumidity != null
        ? '${dragy.currentHumidity!.toStringAsFixed(0)}%'
        : '--%';

    final colors = context.colors;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: colors.subtleBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.subtleBorder),
        ),
        child: Text(
          '$tempStr · $humidityStr · DA: $daStr',
          style: AppTheme.numericFont(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _BlinkingWidget extends StatefulWidget {
  final Widget child;
  final bool isBlinking;
  const _BlinkingWidget({required this.child, required this.isBlinking});

  @override
  State<_BlinkingWidget> createState() => _BlinkingWidgetState();
}

class _BlinkingWidgetState extends State<_BlinkingWidget>
    with TickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isBlinking &&
        !WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      if (!_c.isAnimating) _c.repeat();
      return AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Opacity(
          opacity: _c.value < 0.5 ? 1.0 : 0.0,
          child: child,
        ),
        child: widget.child,
      );
    }
    _c.stop();
    return widget.child;
  }
}


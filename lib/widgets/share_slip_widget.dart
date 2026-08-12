import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_run.dart';
import '../utils/unit_converter.dart';

class ReachedMilestone {
  final String label;
  final double time;
  final double? trapSpeed;

  ReachedMilestone({required this.label, required this.time, this.trapSpeed});
}

class ShareSlipWidget extends StatelessWidget {
  final SavedRun run;
  final String primaryLabel;
  final String primaryTime;
  final List<ReachedMilestone> speedMilestones;
  final List<ReachedMilestone> distanceMilestones;
  final bool isMetric;
  final bool tempInCelsius;
  final bool useNhraRules;

  const ShareSlipWidget({
    super.key,
    required this.run,
    required this.primaryLabel,
    required this.primaryTime,
    required this.speedMilestones,
    required this.distanceMilestones,
    required this.isMetric,
    required this.tempInCelsius,
    required this.useNhraRules,
  });

  @override
  Widget build(BuildContext context) {
    final vehicle = run.vehicleName ?? 'Unknown Vehicle';

    final double startAlt = run.metrics.startAltitude ?? 0.0;
    final double endAlt = run.metrics.history.isNotEmpty
        ? (run.metrics.history.last.altitude ?? startAlt)
        : startAlt;
    final double elevationDiff = endAlt - startAlt;
    final double avgSlope = run.metrics.distanceMeters > 0
        ? (elevationDiff / run.metrics.distanceMeters) * 100
        : 0.0;

    final double displayStartAlt = isMetric
        ? startAlt
        : UnitConverter.metersToFeet(startAlt);
    final double displayElevationDiff = isMetric
        ? elevationDiff
        : UnitConverter.metersToFeet(elevationDiff);
    final String altUnit = isMetric ? 'm' : 'ft';

    final tempC = run.temperature;
    final humidity = run.humidity;
    String weatherStr = 'N/A';
    if (tempC != null && humidity != null) {
      final tempF = UnitConverter.celsiusToFahrenheit(tempC);
      final tempStr = tempInCelsius
          ? '${tempC.toStringAsFixed(1)}°C'
          : '${tempF.toStringAsFixed(0)}°F';

      final daMeters = UnitConverter.calculateDensityAltitude(
        startAlt,
        tempC,
      );
      final daStr = isMetric
          ? '${daMeters.toStringAsFixed(0)}m'
          : '${UnitConverter.metersToFeet(daMeters).toStringAsFixed(0)}ft';

      weatherStr = '$tempStr • ${humidity.toStringAsFixed(0)}% • DA: $daStr';
    }

    return Container(
      width: 400,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a1a1a), Color(0xFF000000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'OpenDragy',
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            vehicle.toUpperCase(),
            style: GoogleFonts.roboto(
              color: Colors.white70,
              fontSize: 14,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 24),

          // Primary Time
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFFBF00).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  primaryTime,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  primaryLabel.toUpperCase(),
                  style: GoogleFonts.roboto(
                    color: const Color(0xFFFFBF00),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Milestones
          if (speedMilestones.isNotEmpty || distanceMilestones.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (speedMilestones.isNotEmpty)
                  _buildMilestoneColumn('SPEED', speedMilestones, isMetric),
                if (speedMilestones.isNotEmpty && distanceMilestones.isNotEmpty)
                  const SizedBox(height: 24),
                if (distanceMilestones.isNotEmpty)
                  _buildMilestoneColumn(
                    'DISTANCE',
                    distanceMilestones,
                    isMetric,
                  ),
              ],
            ),

          if (speedMilestones.isNotEmpty || distanceMilestones.isNotEmpty)
            const SizedBox(height: 24),

          // Footer Info (Weather, Elevation, Date)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'WEATHER',
                      style: GoogleFonts.roboto(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        weatherStr,
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ELEVATION',
                      style: GoogleFonts.roboto(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${displayStartAlt.toStringAsFixed(0)}$altUnit (${displayElevationDiff >= 0 ? '+' : ''}${displayElevationDiff.toStringAsFixed(1)}$altUnit) • Slope: ${avgSlope.toStringAsFixed(2)}%',
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DATE',
                      style: GoogleFonts.roboto(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      run.dateTime.toString().split('.')[0],
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneColumn(
    String title,
    List<ReachedMilestone> milestones,
    bool isMetric,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.roboto(
            color: const Color(0xFFFFBF00),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ...milestones.map((m) {
          String timeDisplay = '${m.time.toStringAsFixed(2)}s';
          if (m.trapSpeed != null) {
            if (!isMetric) {
              timeDisplay +=
                  '@${UnitConverter.kmhToMph(m.trapSpeed!).toStringAsFixed(2)} mph';
            } else {
              timeDisplay += '@${m.trapSpeed!.toStringAsFixed(2)} km/h';
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  m.label,
                  style: GoogleFonts.roboto(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                Text(
                  timeDisplay,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

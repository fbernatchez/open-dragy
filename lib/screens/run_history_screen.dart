import 'package:flutter/material.dart';
import 'package:open_dragy/models/race_metrics.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import '../models/saved_run.dart';
import '../models/race_target.dart';
import '../models/vehicle.dart';
import 'run_detail_screen.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  String _selectedCategory = 'all';
  String _selectedVehicleId = 'all';

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

  List<HistoryCategory> _getCategories(
    List<SavedRun> runs,
    bool isMetric,
    bool useNhraRules,
  ) {
    final Set<String> seenIds = {};
    final List<HistoryCategory> categories = [
      const HistoryCategory(
        id: 'all',
        displayName: 'All Runs',
        isOfficial: true,
      ),
    ];

    for (final run in runs) {
      final completed = getCompletedTests(
        run.metrics,
        useNhraRules: useNhraRules,
      );
      for (final test in completed) {
        if (test.speedUnit != null) {
          final isTestMetric = test.speedUnit == SpeedUnit.kmh;
          if (isTestMetric != isMetric) {
            continue;
          }
        }

        if (!seenIds.contains(test.id)) {
          seenIds.add(test.id);
          categories.add(
            HistoryCategory(
              id: test.id,
              displayName: test.displayName,
              isOfficial: true,
            ),
          );
        }
      }

      if (run.metrics.runMode == 'interval' &&
          run.metrics.targetStartSpeed != null &&
          run.metrics.targetEndSpeed != null) {
        bool matchesAny = false;
        for (final test in officialTests) {
          if (test.startSpeed != null &&
              (run.metrics.targetStartSpeed! - test.startSpeed!).abs() < 0.1 &&
              test.endSpeed != null &&
              (run.metrics.targetEndSpeed! - test.endSpeed!).abs() < 0.1 &&
              run.metrics.targetSpeedUnit == test.speedUnit?.name) {
            matchesAny = true;
            break;
          }
        }

        if (!matchesAny) {
          final unit =
              run.metrics.targetSpeedUnit ?? (isMetric ? 'kmh' : 'mph');
          final start = unit == 'mph'
              ? (run.metrics.targetStartSpeed! * 0.621371).round()
              : run.metrics.targetStartSpeed!.round();
          final end = unit == 'mph'
              ? (run.metrics.targetEndSpeed! * 0.621371).round()
              : run.metrics.targetEndSpeed!.round();
          final customId = 'custom_${start}_${end}_$unit';
          if (!seenIds.contains(customId)) {
            seenIds.add(customId);
            final label = getDisplayLabelForTarget(
              startSpeed: run.metrics.targetStartSpeed,
              endSpeed: run.metrics.targetEndSpeed,
              speedUnit: run.metrics.targetSpeedUnit,
              runMode: 'interval',
            );
            categories.add(
              HistoryCategory(
                id: customId,
                displayName: label,
                isOfficial: false,
                startSpeed: run.metrics.targetStartSpeed,
                endSpeed: run.metrics.targetEndSpeed,
                speedUnit: run.metrics.targetSpeedUnit == 'mph'
                    ? SpeedUnit.mph
                    : SpeedUnit.kmh,
              ),
            );
          }
        }
      }
    }

    final allCategory = categories.first;
    final others = categories.sublist(1);

    others.sort((a, b) {
      if (a.isOfficial && b.isOfficial) {
        final idxA = officialTests.indexWhere((t) => t.id == a.id);
        final idxB = officialTests.indexWhere((t) => t.id == b.id);
        if (idxA != -1 && idxB != -1) {
          return idxA.compareTo(idxB);
        } else if (idxA != -1) {
          return -1;
        } else if (idxB != -1) {
          return 1;
        } else {
          return a.displayName.compareTo(b.displayName);
        }
      } else if (a.isOfficial) {
        return -1;
      } else if (b.isOfficial) {
        return 1;
      } else {
        return a.displayName.compareTo(b.displayName);
      }
    });

    return [allCategory, ...others];
  }

  double? _getPB(String categoryId, List<SavedRun> runs, bool useNhraRules) {
    if (categoryId == 'all') return null;
    double? best;
    for (final run in runs) {
      final val = getCompletedTimeForCategory(
        run.metrics,
        categoryId,
        useNhraRules: useNhraRules,
      );
      if (val != null) {
        if (best == null || val < best) {
          best = val;
        }
      }
    }
    return best;
  }

  List<SavedRun> _getFilteredRuns(
    String categoryId,
    List<SavedRun> runs,
    bool useNhraRules,
  ) {
    if (categoryId == 'all') return runs;
    return runs.where((run) {
      final time = getCompletedTimeForCategory(
        run.metrics,
        categoryId,
        useNhraRules: useNhraRules,
      );
      return time != null;
    }).toList();
  }

  static String getCategoryDisplayName(String categoryId) {
    if (categoryId == 'all') return 'All Runs';
    for (final test in officialTests) {
      if (test.id == categoryId) return test.displayName;
    }
    if (categoryId.startsWith('custom_')) {
      final parts = categoryId.split('_');
      if (parts.length >= 4) {
        final start = double.tryParse(parts[1])?.round() ?? 0;
        final end = double.tryParse(parts[2])?.round() ?? 0;
        final unit = parts[3];
        final displayUnit = unit == 'mph' ? 'mph' : 'km/h';
        return '$start-$end $displayUnit';
      }
    }
    return categoryId;
  }

  void _showVehicleFilterModal(BuildContext context, List<MapEntry<String, String>> availableVehicles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.only(top: 24, bottom: 32, left: 24, right: 24),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Vehicle',
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildFilterOption(
                context,
                id: 'all',
                title: 'All Vehicles',
                isSelected: _selectedVehicleId == 'all',
              ),
              if (availableVehicles.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                ...availableVehicles.map((v) => _buildFilterOption(
                      context,
                      id: v.key,
                      title: v.value,
                      isSelected: _selectedVehicleId == v.key,
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(
    BuildContext context, {
    required String id,
    required String title,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedVehicleId = id;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFBF00).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFBF00).withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.roboto(
                  color: isSelected ? const Color(0xFFFFBF00) : Colors.white,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFFFBF00), size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);

    final Map<String, String> uniqueVehicles = {};
    for (var run in dragy.savedRuns) {
      if (run.vehicleId != null && run.vehicleName != null) {
        uniqueVehicles[run.vehicleId!] = run.vehicleName!;
      }
    }
    final availableVehicles = uniqueVehicles.entries.toList();
    List<SavedRun> baseRuns = dragy.savedRuns;

    if (_selectedVehicleId != 'all') {
      baseRuns = baseRuns
          .where((r) => r.vehicleId == _selectedVehicleId)
          .toList();
    }
    final runs = baseRuns;
    final isMetric = dragy.isMetric;
    final useNhraRules = dragy.useNhraRules;

    final categories = _getCategories(runs, isMetric, useNhraRules);
    if (!categories.any((c) => c.id == _selectedCategory)) {
      _selectedCategory = 'all';
    }
    final filteredRuns = _getFilteredRuns(
      _selectedCategory,
      runs,
      useNhraRules,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'Run History',
          style: GoogleFonts.comfortaa(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _selectedVehicleId == 'all'
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt,
              color: _selectedVehicleId == 'all'
                  ? Colors.white
                  : const Color(0xFFFFBF00),
            ),
            tooltip: 'Filter by Vehicle',
            onPressed: () => _showVehicleFilterModal(context, availableVehicles),
          ),
        ],
      ),
      body: runs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey.shade800),
                  const SizedBox(height: 16),
                  Text(
                    'No runs recorded yet.',
                    style: GoogleFonts.roboto(
                      color: Colors.white54,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Perform a speed run to automatically log it.',
                    style: GoogleFonts.roboto(
                      color: Colors.white38,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Horizontal category PB cards list
                SizedBox(
                  height: 96,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, idx) {
                      final category = categories[idx];
                      final isSelected = _selectedCategory == category.id;
                      final label = category.displayName;
                      final pb = _getPB(category.id, runs, useNhraRules);

                      String pbText = '-.--s';
                      if (category.id == 'all') {
                        pbText = '${runs.length} Runs';
                      } else if (pb != null) {
                        pbText = '${pb.toStringAsFixed(2)}s';
                      }

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = category.id;
                          });
                        },
                        child: Container(
                          width: 105,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFFFBF00).withOpacity(0.12)
                                : const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFFFBF00)
                                  : Colors.white.withOpacity(0.08),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFFBF00,
                                      ).withOpacity(0.15),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.roboto(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFFFFBF00)
                                      : Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pbText,
                                style: GoogleFonts.robotoMono(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                // Runs list
                Expanded(
                  child: filteredRuns.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.filter_list_off,
                                size: 50,
                                color: Colors.grey.shade800,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No runs found for this category.',
                                style: GoogleFonts.roboto(
                                  color: Colors.white38,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: filteredRuns.length,
                          itemBuilder: (context, index) {
                            final run = filteredRuns[index];
                            return RunHistoryCard(
                              run: run,
                              formattedDate: _formatDate(run.dateTime),
                              selectedCategory: _selectedCategory,
                              onDelete: () =>
                                  _confirmDelete(context, dragy, run),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  void _confirmDelete(BuildContext context, DragyProvider dragy, SavedRun run) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Delete Run', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete this run from your history?',
          style: TextStyle(color: Colors.white70),
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
              dragy.deleteRun(run.id);
              Navigator.pop(context);
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
}

class RunHistoryCard extends StatelessWidget {
  final SavedRun run;
  final String formattedDate;
  final String selectedCategory;
  final VoidCallback onDelete;

  const RunHistoryCard({
    super.key,
    required this.run,
    required this.formattedDate,
    required this.selectedCategory,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;
    final metrics = run.metrics;

    // Decide which milestone display is primary
    String primaryLabel = "0-60";
    String primaryTime = "-.--s";

    final useNhraRulesSetting = dragy.useNhraRules;

    if (selectedCategory != 'all') {
      primaryLabel = _RunHistoryScreenState.getCategoryDisplayName(
        selectedCategory,
      );
      final displayTime = getCompletedTimeForCategory(
        metrics,
        selectedCategory,
        useNhraRules: useNhraRulesSetting,
      );
      if (displayTime != null) {
        primaryTime = "${displayTime.toStringAsFixed(2)}s";
      }
    } else {
      final completed = getCompletedTests(
        metrics,
        useNhraRules: useNhraRulesSetting,
      );
      double maxTime = -1.0;

      for (final test in completed) {
        final t = getCompletedTimeForCategory(
          metrics,
          test.id,
          useNhraRules: useNhraRulesSetting,
        );
        if (t != null && t > maxTime) {
          maxTime = t;
          primaryLabel = test.displayName;
          primaryTime = "${t.toStringAsFixed(2)}s";
        }
      }

      if (maxTime < 0 &&
          metrics.runMode == 'interval' &&
          metrics.targetStartSpeed != null &&
          metrics.targetEndSpeed != null) {
        primaryLabel = getDisplayLabelForTarget(
          startSpeed: metrics.targetStartSpeed,
          endSpeed: metrics.targetEndSpeed,
          speedUnit: metrics.targetSpeedUnit,
          runMode: 'interval',
        );
        final unit = metrics.targetSpeedUnit ?? (isMetric ? 'kmh' : 'mph');
        final start = unit == 'mph'
            ? (metrics.targetStartSpeed! * 0.621371).round()
            : metrics.targetStartSpeed!.round();
        final end = unit == 'mph'
            ? (metrics.targetEndSpeed! * 0.621371).round()
            : metrics.targetEndSpeed!.round();
        final customId = 'custom_${start}_${end}_$unit';
        final compTime = getCompletedTimeForCategory(
          metrics,
          customId,
          useNhraRules: useNhraRulesSetting,
        );
        primaryTime = compTime != null
            ? "${compTime.toStringAsFixed(2)}s"
            : "-.--s";
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

    return Dismissible(
      key: Key(run.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.redAccent,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        onDelete();
        return false; // dialog handles delete action
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RunDetailScreen(run: run),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 14.0,
            ),
            child: Row(
              children: [
                // Highlight circle
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSlopeValid
                          ? const Color(0xFF39FF14).withOpacity(0.3)
                          : Colors.redAccent.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        primaryLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: GoogleFonts.roboto(
                          fontSize: 9,
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        primaryTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: GoogleFonts.robotoMono(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Run details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedDate,
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
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
                          const SizedBox(width: 4),
                          Text(
                            isSlopeValid ? 'Valid' : 'Invalid',
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              color: isSlopeValid
                                  ? Colors.white70
                                  : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            '•',
                            style: TextStyle(color: Colors.white38),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Duration: ${metrics.elapsedTime.toStringAsFixed(1)}s',
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      if (run.vehicleName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_car,
                              size: 12,
                              color: Color(0xFFFFBF00),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                run.vehicleName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.roboto(
                                  fontSize: 11,
                                  color: const Color(0xFFFFBF00),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (run.notes != null &&
                          run.notes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.note_alt_outlined,
                              size: 12,
                              color: Color(0xFFFFBF00),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                run.notes!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.roboto(
                                  fontSize: 11,
                                  color: Colors.white38,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Arrow
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

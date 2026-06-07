import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dragy_provider.dart';
import '../models/saved_run.dart';
import '../models/race_metrics.dart';
import 'run_detail_screen.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  String _selectedCategory = 'All';

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

  static List<String> getCompletedMilestones(
    RaceMetrics metrics,
    bool isMetric,
  ) {
    final List<String> milestones = [];

    // Drag distance/time milestones
    if (metrics.time60ft != null) milestones.add('60ft');

    if (isMetric) {
      if (metrics.time0to100kmh != null) milestones.add('0-100 km/h');
      if (metrics.time0to200kmh != null) milestones.add('0-200 km/h');
    } else {
      if (metrics.time0to60mph != null) milestones.add('0-60 mph');
      if (metrics.time0to130mph != null) milestones.add('0-130 mph');
    }

    if (metrics.time18Mile != null) milestones.add('1/8 mile');
    if (metrics.time1000ft != null) milestones.add('1000ft');
    if (metrics.time14Mile != null) milestones.add('1/4 mile');
    if (metrics.time12Mile != null) milestones.add('1/2 mile');

    // Rolling milestones
    if (metrics.time60to130mph != null) milestones.add('60-130 mph');
    if (metrics.time100to200kmh != null) milestones.add('100-200 km/h');

    // Custom target label if present
    if (metrics.targetLabel != null && metrics.targetLabel!.isNotEmpty) {
      final standardLabels = {
        '60ft',
        '0-100 km/h',
        '0-200 km/h',
        '0-60 mph',
        '0-130 mph',
        '1/8 mile',
        '1000ft',
        '1/4 mile',
        '1/2 mile',
        '60-130 mph',
        '100-200 km/h',
        '60-130',
        '100-200',
      };
      if (!standardLabels.contains(metrics.targetLabel)) {
        milestones.add(metrics.targetLabel!);
      }
    }

    return milestones;
  }

  static double? getCompletedTimeForMilestone(
    RaceMetrics metrics,
    String milestone,
    bool isMetric,
  ) {
    switch (milestone) {
      case '60ft':
        return metrics.time60ft;
      case '0-60 mph':
        return metrics.time0to60mph;
      case '0-100 km/h':
        return metrics.time0to100kmh;
      case '1/8 mile':
        return metrics.time18Mile;
      case '1000ft':
        return metrics.time1000ft;
      case '1/4 mile':
        return metrics.time14Mile;
      case '1/2 mile':
        return metrics.time12Mile;
      case '60-130 mph':
        return metrics.time60to130mph;
      case '100-200 km/h':
        return metrics.time100to200kmh;
      case '0-130 mph':
        return metrics.time0to130mph;
      case '0-200 km/h':
        return metrics.time0to200kmh;
      default:
        if (metrics.targetLabel == milestone) {
          return metrics.elapsedTime > 0 ? metrics.elapsedTime : null;
        }
        return null;
    }
  }

  List<String> _getCategories(List<SavedRun> runs, bool isMetric) {
    final Set<String> categories = {'All'};
    for (final run in runs) {
      final milestones = getCompletedMilestones(run.metrics, isMetric);
      categories.addAll(milestones);
    }
    final list = categories.toList();
    if (list.length > 1) {
      final order = [
        '60ft',
        '0-60 mph',
        '0-100 km/h',
        '1/8 mile',
        '1000ft',
        '1/4 mile',
        '1/2 mile',
        '60-130 mph',
        '100-200 km/h',
        '0-130 mph',
        '0-200 km/h',
      ];
      final others = list.sublist(1)
        ..sort((a, b) {
          final idxA = order.indexOf(a);
          final idxB = order.indexOf(b);
          if (idxA != -1 && idxB != -1) {
            return idxA.compareTo(idxB);
          } else if (idxA != -1) {
            return -1;
          } else if (idxB != -1) {
            return 1;
          } else {
            return a.compareTo(b);
          }
        });
      return ['All', ...others];
    }
    return list;
  }

  static double? getCompletedTime(RaceMetrics metrics, bool isMetric) {
    if (metrics.runMode == 'rolling') {
      if (metrics.targetLabel == '60-130 mph' ||
          metrics.targetLabel == '60-130') {
        return metrics.time60to130mph;
      } else if (metrics.targetLabel == '100-200 km/h' ||
          metrics.targetLabel == '100-200') {
        return metrics.time100to200kmh;
      } else if (metrics.targetLabel == '0-60 mph') {
        return metrics.time0to60mph;
      } else if (metrics.targetLabel == '0-100 km/h') {
        return metrics.time0to100kmh;
      } else {
        return metrics.elapsedTime > 0 ? metrics.elapsedTime : null;
      }
    } else {
      if (metrics.time12Mile != null) return metrics.time12Mile;
      if (metrics.time14Mile != null) return metrics.time14Mile;
      if (metrics.time1000ft != null) return metrics.time1000ft;
      if (metrics.time18Mile != null) return metrics.time18Mile;
      if (metrics.time0to100kmh != null && isMetric)
        return metrics.time0to100kmh;
      if (metrics.time0to60mph != null && !isMetric)
        return metrics.time0to60mph;
      if (metrics.time60ft != null) return metrics.time60ft;
      return metrics.elapsedTime > 0 ? metrics.elapsedTime : null;
    }
  }

  double? _getPB(String category, List<SavedRun> runs, bool isMetric) {
    if (category == 'All') return null;
    double? best;
    for (final run in runs) {
      final val = getCompletedTimeForMilestone(run.metrics, category, isMetric);
      if (val != null) {
        if (best == null || val < best) {
          best = val;
        }
      }
    }
    return best;
  }

  List<SavedRun> _getFilteredRuns(
    String category,
    List<SavedRun> runs,
    bool isMetric,
  ) {
    if (category == 'All') return runs;
    return runs.where((run) {
      final time = getCompletedTimeForMilestone(
        run.metrics,
        category,
        isMetric,
      );
      return time != null;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final runs = dragy.savedRuns;
    final isMetric = dragy.isMetric;

    final categories = _getCategories(runs, isMetric);
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }
    final filteredRuns = _getFilteredRuns(_selectedCategory, runs, isMetric);

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
                      final isSelected = _selectedCategory == category;
                      final label = category == 'All' ? 'All Runs' : category;
                      final pb = _getPB(category, runs, isMetric);

                      String pbText = '-.--s';
                      if (category == 'All') {
                        pbText = '${runs.length} Runs';
                      } else if (pb != null) {
                        pbText = '${pb.toStringAsFixed(2)}s';
                      }

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedCategory = category;
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

    if (selectedCategory != 'All') {
      primaryLabel = selectedCategory;
      final displayTime = _RunHistoryScreenState.getCompletedTimeForMilestone(
        metrics,
        selectedCategory,
        isMetric,
      );
      if (displayTime != null) {
        primaryTime = "${displayTime.toStringAsFixed(2)}s";
      }
    } else {
      if (metrics.time12Mile != null) {
        primaryLabel = "1/2 mile";
        primaryTime = "${metrics.time12Mile!.toStringAsFixed(2)}s";
      } else if (metrics.time14Mile != null) {
        primaryLabel = "1/4 mile";
        primaryTime = "${metrics.time14Mile!.toStringAsFixed(2)}s";
      } else if (isMetric && metrics.time0to200kmh != null) {
        primaryLabel = "0-200";
        primaryTime = "${metrics.time0to200kmh!.toStringAsFixed(2)}s";
      } else if (!isMetric && metrics.time0to130mph != null) {
        primaryLabel = "0-130";
        primaryTime = "${metrics.time0to130mph!.toStringAsFixed(2)}s";
      } else if (isMetric && metrics.time100to200kmh != null) {
        primaryLabel = "100-200";
        primaryTime = "${metrics.time100to200kmh!.toStringAsFixed(2)}s";
      } else if (!isMetric && metrics.time60to130mph != null) {
        primaryLabel = "60-130";
        primaryTime = "${metrics.time60to130mph!.toStringAsFixed(2)}s";
      } else if (metrics.time100to200kmh != null) {
        primaryLabel = "100-200";
        primaryTime = "${metrics.time100to200kmh!.toStringAsFixed(2)}s";
      } else if (metrics.time60to130mph != null) {
        primaryLabel = "60-130";
        primaryTime = "${metrics.time60to130mph!.toStringAsFixed(2)}s";
      } else if (metrics.time0to200kmh != null) {
        primaryLabel = "0-200";
        primaryTime = "${metrics.time0to200kmh!.toStringAsFixed(2)}s";
      } else if (metrics.time0to130mph != null) {
        primaryLabel = "0-130";
        primaryTime = "${metrics.time0to130mph!.toStringAsFixed(2)}s";
      } else if (metrics.time1000ft != null) {
        primaryLabel = "1000ft";
        primaryTime = "${metrics.time1000ft!.toStringAsFixed(2)}s";
      } else if (metrics.time18Mile != null) {
        primaryLabel = "1/8 mile";
        primaryTime = "${metrics.time18Mile!.toStringAsFixed(2)}s";
      } else if (metrics.runMode == 'rolling' && metrics.targetLabel != null) {
        primaryLabel = metrics.targetLabel!;
        primaryTime = "${metrics.elapsedTime.toStringAsFixed(2)}s";
      } else if (isMetric && metrics.time0to100kmh != null) {
        primaryLabel = "0-100";
        primaryTime = "${metrics.time0to100kmh!.toStringAsFixed(2)}s";
      } else if (!isMetric && metrics.time0to60mph != null) {
        primaryLabel = "0-60";
        primaryTime = "${metrics.time0to60mph!.toStringAsFixed(2)}s";
      } else if (metrics.time0to100kmh != null) {
        primaryLabel = "0-100";
        primaryTime = "${metrics.time0to100kmh!.toStringAsFixed(2)}s";
      } else if (metrics.time0to60mph != null) {
        primaryLabel = "0-60";
        primaryTime = "${metrics.time0to60mph!.toStringAsFixed(2)}s";
      } else if (metrics.time60ft != null) {
        primaryLabel = "60ft";
        primaryTime = "${metrics.time60ft!.toStringAsFixed(2)}s";
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

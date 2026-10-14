import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../models/saved_run.dart';
import '../theme/app_theme.dart';
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
        if (!test.matchesUnitSystem(isMetric)) {
          continue;
        }

        if (!seenIds.contains(test.id)) {
          seenIds.add(test.id);
          categories.add(
            HistoryCategory(
              id: test.id,
              displayName: test.displayName,
              isOfficial: test.isOfficial,
              startSpeed: test.startSpeed,
              endSpeed: test.endSpeed,
              speedUnit: test.speedUnit,
            ),
          );
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
    bool isMetric,
  ) {
    if (categoryId == 'all') {
      return runs.where((run) {
        if (run.metrics.runMode == RunMode.interval) {
          final runIsMetric = (run.metrics.testSpeedUnit ?? SpeedUnit.kmh) == SpeedUnit.kmh;
          return runIsMetric == isMetric;
        }
        return true;
      }).toList();
    }
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

  void _showVehicleFilterModal(
    BuildContext context,
    List<MapEntry<String, String>> availableVehicles,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final colors = context.colors;
        return Container(
          padding: const EdgeInsets.only(
            top: 24,
            bottom: 32,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Vehicle',
                style: AppTheme.brandFont(
                  color: colors.textPrimary,
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(color: colors.cardBorder, height: 1),
                ),
                ...availableVehicles.map(
                  (v) => _buildFilterOption(
                    context,
                    id: v.key,
                    title: v.value,
                    isSelected: _selectedVehicleId == v.key,
                  ),
                ),
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
    final colors = context.colors;
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
          color: isSelected
              ? colors.accent.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colors.accent.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTheme.font(
                  color: isSelected ? colors.accent : colors.textPrimary,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: colors.accent,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final savedRuns = dragy.savedRuns;
    final isMetric = dragy.isMetric;
    final useNhraRules = dragy.useNhraRules;

    final Map<String, String> uniqueVehicles = {};
    for (var run in savedRuns) {
      if (run.vehicleId != null && run.vehicleName != null) {
        uniqueVehicles[run.vehicleId!] = run.vehicleName!;
      }
    }
    final availableVehicles = uniqueVehicles.entries.toList();
    List<SavedRun> baseRuns = savedRuns;

    if (_selectedVehicleId != 'all') {
      baseRuns = baseRuns
          .where((r) => r.vehicleId == _selectedVehicleId)
          .toList();
    }
    final runs = baseRuns;

    final categories = _getCategories(runs, isMetric, useNhraRules);
    if (!categories.any((c) => c.id == _selectedCategory)) {
      _selectedCategory = 'all';
    }
    final filteredRuns = _getFilteredRuns(
      _selectedCategory,
      runs,
      useNhraRules,
      isMetric,
    );

    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Run History'),
        actions: [
          IconButton(
            icon: Icon(
              _selectedVehicleId == 'all'
                  ? Icons.filter_alt_outlined
                  : Icons.filter_alt,
              color: _selectedVehicleId == 'all'
                  ? colors.textPrimary
                  : colors.accent,
            ),
            tooltip: 'Filter by Vehicle',
            onPressed: () =>
                _showVehicleFilterModal(context, availableVehicles),
          ),
        ],
      ),
      body: runs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: colors.instrumentRing),
                  const SizedBox(height: 16),
                  Text(
                    'No runs recorded yet.',
                    style: AppTheme.font(
                      color: colors.textSecondary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Perform a speed run to automatically log it.',
                    style: AppTheme.font(
                      color: colors.textMuted,
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
                                ? colors.accent.withOpacity(0.12)
                                : colors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? colors.accent
                                  : colors.cardBorder,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: colors.accent.withOpacity(0.15),
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
                                style: AppTheme.font(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? colors.accent
                                      : colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pbText,
                                style: AppTheme.numericFont(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? colors.textPrimary
                                      : colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Divider(color: colors.cardBorder, height: 1),
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
                                color: colors.instrumentRing,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No runs found for this category.',
                                style: AppTheme.font(
                                  color: colors.textMuted,
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
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Run', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Are you sure you want to permanently delete this run from your history?',
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
              dragy.deleteRun(run.id);
              Navigator.pop(context);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: colors.statusDanger),
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
        if (!test.matchesUnitSystem(dragy.isMetric)) {
          continue;
        }
        final t = getCompletedTimeForCategory(
          metrics,
          test.id,
          useNhraRules: useNhraRulesSetting,
          activeTests: completed,
        );
        if (t != null && t > maxTime) {
          maxTime = t;
          primaryLabel = test.displayName;
          primaryTime = "${t.toStringAsFixed(2)}s";
        }
      }
    }

    final bool isSlopeValid = metrics.isSlopeValid;

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
          color: context.colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.cardBorder, width: 1),
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
                    color: context.colors.subtleBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSlopeValid
                          ? context.colors.accentSecondary.withOpacity(0.3)
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
                        style: AppTheme.font(
                          fontSize: 9,
                          color: context.colors.textMuted,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        primaryTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: AppTheme.numericFont(
                          fontSize: 15,
                          color: context.colors.textPrimary,
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
                        style: AppTheme.font(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
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
                                ? context.colors.accentSecondary
                                : Colors.redAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSlopeValid ? 'Valid' : 'Invalid',
                            style: AppTheme.font(
                              fontSize: 12,
                              color: isSlopeValid
                                  ? context.colors.textSecondary
                                  : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '•',
                            style: TextStyle(color: context.colors.textMuted),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Duration: ${metrics.elapsedTime.toStringAsFixed(1)}s',
                            style: AppTheme.font(
                              fontSize: 12,
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (run.vehicleName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              size: 12,
                              color: context.colors.accent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                run.vehicleName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.font(
                                  fontSize: 11,
                                  color: context.colors.accent,
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
                            Icon(
                              Icons.note_alt_outlined,
                              size: 12,
                              color: context.colors.accent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                run.notes!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.font(
                                  fontSize: 11,
                                  color: context.colors.textMuted,
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
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: context.colors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

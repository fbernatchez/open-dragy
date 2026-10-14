import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../utils/unit_converter.dart';
import '../widgets/app_segmented_switch.dart';
import '../theme/app_theme.dart';

class TestSelectionScreen extends StatelessWidget {
  const TestSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;
    final colors = context.colors;

    final visibleCustom = dragy.customTests
        .where((t) => t.matchesUnitSystem(isMetric))
        .toList();

    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Active Tests'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showAddCustomTestDialog(context, dragy),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Default'),
                  Tab(text: 'Custom'),
                ],
              ),
              elevation: 0,
            ),
            body: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.only(bottom: 100, top: 8),
                  children: [
                    ...officialTests
                        .where((t) {
                          if (t.distance != null) return true;
                          return t.speedUnit ==
                              (isMetric ? SpeedUnit.kmh : SpeedUnit.mph);
                        })
                        .map((test) {
                      return _TestTile(
                        test: test,
                        isEnabled: dragy.enabledTests.contains(test.id),
                        onChanged: (val) =>
                            dragy.toggleTestEnabled(test.id, val),
                      );
                    }),
                  ],
                ),
                visibleCustom.isEmpty
                    ? Center(
                        child: Text(
                          'No Custom Tests yet.',
                          style: AppTheme.font(color: colors.textMuted),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 100, top: 8),
                        children: [
                          ...visibleCustom.map(
                            (test) => _TestTile(
                              test: test,
                              onDelete: () => dragy.removeCustomTest(test.id),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddCustomTestDialog(BuildContext context, DragyProvider dragy) {
    showDialog<bool>(
      context: context,
      builder: (context) => _AddCustomTestDialog(dragy: dragy),
    ).then((result) {
      if (result == true && context.mounted) {
        DefaultTabController.of(context).animateTo(1);
      }
    });
  }
}

class _TestTile extends StatelessWidget {
  final RaceTest test;
  final bool isEnabled;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onDelete;

  const _TestTile({
    required this.test,
    this.isEnabled = true,
    this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Widget iconContainer = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isEnabled
            ? const Color(0xFF1565C0).withValues(alpha: 0.2)
            : colors.subtleBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        test.distance != null ? Icons.flag_outlined : Icons.speed,
        color: isEnabled ? const Color(0xFF42A5F5) : colors.textMuted,
        size: 22,
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: onDelete != null
          ? ListTile(
              leading: iconContainer,
              title: Text(
                test.displayName,
                style: AppTheme.font(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline, color: colors.textMuted),
                onPressed: onDelete,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            )
          : SwitchListTile(
              secondary: iconContainer,
              title: Text(
                test.displayName,
                style: AppTheme.font(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              value: isEnabled,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFF42A5F5),
              activeTrackColor: const Color(0xFF1565C0),
              inactiveThumbColor:
                  context.isDark ? colors.textMuted : const Color(0xFF8E8E93),
              inactiveTrackColor:
                  context.isDark ? Colors.white12 : const Color(0xFFE5E5EA),
              trackOutlineColor:
                  const WidgetStatePropertyAll(Colors.transparent),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
    );
  }
}

class _AddCustomTestDialog extends StatefulWidget {
  final DragyProvider dragy;
  const _AddCustomTestDialog({required this.dragy});

  @override
  State<_AddCustomTestDialog> createState() => _AddCustomTestDialogState();
}

class _AddCustomTestDialogState extends State<_AddCustomTestDialog> {
  bool isDistanceMode = false;
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMetric = widget.dragy.isMetric;
    final speedUnit = isMetric ? 'km/h' : 'mph';
    final distUnit = isMetric ? 'm' : 'ft';

    return AlertDialog(
      title: Text(
        'New Custom Test',
        style: AppTheme.font(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSegmentedSwitch<bool>(
            selectedValue: isDistanceMode,
            items: const [
              SegmentedSwitchItem(
                value: false,
                label: 'Speed',
              ),
              SegmentedSwitchItem(
                value: true,
                label: 'Distance',
              ),
            ],
            onChanged: (val) {
              if (isDistanceMode != val) {
                setState(() => isDistanceMode = val);
              }
            },
          ),
          const SizedBox(height: 16),
          if (!isDistanceMode)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Start ($speedUnit)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.subtleBorder),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'End ($speedUnit)',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.subtleBorder),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            TextField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Distance ($distUnit)',
                labelStyle: TextStyle(color: colors.textMuted),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: colors.subtleBorder),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTheme.font(color: colors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () {
            if (isDistanceMode) {
              final dist = double.tryParse(_distanceController.text);
              if (dist != null && dist > 0) {
                final isMetric = widget.dragy.isMetric;
                final distInt = dist.round();
                final unit = isMetric ? DistanceUnit.meter : DistanceUnit.feet;
                final unitStr = isMetric ? 'm' : 'ft';
                final test = RaceTest(
                  id: 'custom_dist_${distInt}_${unit.name}',
                  displayName: '$distInt$unitStr',
                  distance: dist,
                  distanceUnit: unit,
                  isOfficial: false,
                );
                widget.dragy.addCustomTest(test);
                Navigator.pop(context, true);
              }
            } else {
              final start = double.tryParse(_startController.text);
              final end = double.tryParse(_endController.text);
              if (start != null && end != null && start != end) {
                final isMetric = widget.dragy.isMetric;
                final unit = isMetric ? SpeedUnit.kmh : SpeedUnit.mph;
                final unitStr = isMetric ? 'km/h' : 'mph';
                final startInt = start.round();
                final endInt = end.round();

                final test = RaceTest(
                  id: 'custom_${startInt}_${endInt}_${unit.name}',
                  displayName: '$startInt-$endInt $unitStr',
                  startSpeed: isMetric ? start : UnitConverter.mphToKmh(start),
                  endSpeed: isMetric ? end : UnitConverter.mphToKmh(end),
                  speedUnit: unit,
                  isOfficial: false,
                );

                widget.dragy.addCustomTest(test);
                Navigator.pop(context, true);
              }
            }
          },
          child: Text(
            'Add',
            style: AppTheme.font(color: const Color(0xFF42A5F5)),
          ),
        ),
      ],
    );
  }
}

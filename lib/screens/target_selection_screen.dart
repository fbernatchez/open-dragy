import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../models/race_target.dart';

class TargetSelectionScreen extends StatelessWidget {
  const TargetSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Active Targets',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1565C0),
        onPressed: () => _showAddCustomTargetDialog(context, dragy),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add Custom Interval',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          _SectionHeader(label: 'Official Milestones'),
          ...officialTests
              .where((t) {
                if (t.distance != null)
                  return true; // official distance targets always shown
                return t.speedUnit ==
                    (isMetric ? SpeedUnit.kmh : SpeedUnit.mph);
              })
              .map((target) {
                return _TargetTile(
                  target: target,
                  isEnabled: dragy.enabledTargets.contains(target.id),
                  onChanged: (val) => dragy.toggleTargetEnabled(target.id, val),
                );
              }),

          ...[
            Builder(
              builder: (context) {
                final visibleCustom = dragy.customTargets.where(
                  (t) =>
                      (t.distance != null &&
                          t.distanceUnit ==
                              (isMetric
                                  ? DistanceUnit.meter
                                  : DistanceUnit.feet)) ||
                      t.speedUnit ==
                          (isMetric ? SpeedUnit.kmh : SpeedUnit.mph),
                ).toList();
                if (visibleCustom.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(label: 'Custom Intervals'),
                    ...visibleCustom.map((target) => _TargetTile(
                          target: target,
                          isEnabled: dragy.enabledTargets.contains(target.id),
                          onChanged: (val) =>
                              dragy.toggleTargetEnabled(target.id, val),
                          onDelete: () => dragy.removeCustomTarget(target.id),
                        )),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showAddCustomTargetDialog(BuildContext context, DragyProvider dragy) {
    showDialog(
      context: context,
      builder: (context) => _AddCustomTargetDialog(dragy: dragy),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.roboto(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final RaceTarget target;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onDelete;

  const _TargetTile({
    required this.target,
    required this.isEnabled,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: SwitchListTile(
        secondary: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                onPressed: onDelete,
              )
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? const Color(0xFF1565C0).withOpacity(0.2)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  target.distance != null ? Icons.flag_outlined : Icons.speed,
                  color: isEnabled ? const Color(0xFF42A5F5) : Colors.white38,
                  size: 22,
                ),
              ),
        title: Text(
          target.displayName,
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: target.distance != null
            ? Text(
                'Distance target',
                style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
              )
            : Text(
                'Speed interval',
                style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
              ),
        value: isEnabled,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF42A5F5),
        activeTrackColor: const Color(0xFF1565C0),
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _AddCustomTargetDialog extends StatefulWidget {
  final DragyProvider dragy;
  const _AddCustomTargetDialog({required this.dragy});

  @override
  State<_AddCustomTargetDialog> createState() => _AddCustomTargetDialogState();
}

class _AddCustomTargetDialogState extends State<_AddCustomTargetDialog> {
  bool isDistanceMode = false;
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isMetric = widget.dragy.isMetric;
    final speedUnit = isMetric ? 'km/h' : 'mph';
    final distUnit = isMetric ? 'm' : 'ft';
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        'New Custom Target',
        style: GoogleFonts.roboto(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Speed'),
                selected: !isDistanceMode,
                onSelected: (val) {
                  if (val) setState(() => isDistanceMode = false);
                },
                selectedColor: const Color(0xFF1565C0),
                backgroundColor: Colors.white12,
                labelStyle: TextStyle(
                  color: !isDistanceMode ? Colors.white : Colors.white54,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Distance'),
                selected: isDistanceMode,
                onSelected: (val) {
                  if (val) setState(() => isDistanceMode = true);
                },
                selectedColor: const Color(0xFF1565C0),
                backgroundColor: Colors.white12,
                labelStyle: TextStyle(
                  color: isDistanceMode ? Colors.white : Colors.white54,
                ),
              ),
            ],
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Start ($speedUnit)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'End ($speedUnit)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Distance ($distUnit)',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
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
            style: GoogleFonts.roboto(color: Colors.white54),
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
                final target = RaceTarget(
                  id: 'custom_dist_${distInt}_${unit.name}',
                  displayName: '$distInt$unitStr',
                  distance: dist,
                  distanceUnit: unit,
                  isOfficial: false,
                );
                widget.dragy.addCustomTarget(target);
                Navigator.pop(context);
              }
            } else {
              final start = double.tryParse(_startController.text);
              final end = double.tryParse(_endController.text);
              if (start != null && end != null && end > start) {
                final isMetric = widget.dragy.isMetric;
                final unit = isMetric ? SpeedUnit.kmh : SpeedUnit.mph;
                final unitStr = isMetric ? 'km/h' : 'mph';
                final startInt = start.round();
                final endInt = end.round();

                final target = RaceTarget(
                  id: 'custom_${startInt}_${endInt}_${unit.name}',
                  displayName: '$startInt-$endInt $unitStr',
                  startSpeed: isMetric ? start : start * 1.609344,
                  endSpeed: isMetric ? end : end * 1.609344,
                  speedUnit: unit,
                  isOfficial: false,
                );

                widget.dragy.addCustomTarget(target);
                Navigator.pop(context);
              }
            }
          },
          child: Text(
            'Add',
            style: GoogleFonts.roboto(color: const Color(0xFF42A5F5)),
          ),
        ),
      ],
    );
  }
}

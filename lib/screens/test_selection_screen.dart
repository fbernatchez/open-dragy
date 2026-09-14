import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/race_test.dart';
import '../providers/dragy_provider.dart';
import '../utils/unit_converter.dart';

class TestSelectionScreen extends StatelessWidget {
  const TestSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final isMetric = dragy.isMetric;

    final visibleCustom = dragy.customTests
        .where(
          (t) =>
              (t.distance != null &&
                  t.distanceUnit ==
                      (isMetric ? DistanceUnit.meter : DistanceUnit.feet)) ||
              t.speedUnit == (isMetric ? SpeedUnit.kmh : SpeedUnit.mph),
        )
        .toList();

    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: const Color(0xFF1565C0),
              iconTheme: const IconThemeData(color: Colors.white),
              title: Text(
                'Active Tests',
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showaddCustomTestDialog(context, dragy),
                ),
              ],
              bottom: TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
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
                    onChanged: (val) => dragy.toggleTestEnabled(test.id, val),
                  );
                }),
              ],
            ),
            visibleCustom.isEmpty
                ? Center(
                    child: Text(
                      'No Custom Tests yet.',
                      style: GoogleFonts.roboto(color: Colors.white54),
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

  void _showaddCustomTestDialog(BuildContext context, DragyProvider dragy) {
    showDialog<bool>(
      context: context,
      builder: (context) => _addCustomTestDialog(dragy: dragy),
    ).then((result) {
      if (result == true) {
        DefaultTabController.of(context).animateTo(1);
      }
    });
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
    final Widget iconContainer = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isEnabled
            ? const Color(0xFF1565C0).withOpacity(0.2)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        test.distance != null ? Icons.flag_outlined : Icons.speed,
        color: isEnabled ? const Color(0xFF42A5F5) : Colors.white38,
        size: 22,
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: onDelete != null
          ? ListTile(
              leading: iconContainer,
              title: Text(
                test.displayName,
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                onPressed: onDelete,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            )
          : SwitchListTile(
              secondary: iconContainer,
              title: Text(
                test.displayName,
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              value: isEnabled,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFF42A5F5),
              activeTrackColor: const Color(0xFF1565C0),
              inactiveThumbColor: Colors.white38,
              inactiveTrackColor: Colors.white12,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
    );
  }
}

class _addCustomTestDialog extends StatefulWidget {
  final DragyProvider dragy;
  const _addCustomTestDialog({required this.dragy});

  @override
  State<_addCustomTestDialog> createState() => _addCustomTestDialogState();
}

class _addCustomTestDialogState extends State<_addCustomTestDialog> {
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
        'New Custom Test',
        style: GoogleFonts.roboto(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                _DialogModeButton(
                  label: 'Speed',
                  isActive: !isDistanceMode,
                  onTap: () {
                    if (isDistanceMode) setState(() => isDistanceMode = false);
                  },
                ),
                _DialogModeButton(
                  label: 'Distance',
                  isActive: isDistanceMode,
                  onTap: () {
                    if (!isDistanceMode) setState(() => isDistanceMode = true);
                  },
                ),
              ],
            ),
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
            style: GoogleFonts.roboto(color: const Color(0xFF42A5F5)),
          ),
        ),
      ],
    );
  }
}

class _DialogModeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DialogModeButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1565C0) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.robotoMono(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

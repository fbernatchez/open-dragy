import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/app_cues.dart';
import '../providers/dragy_provider.dart';

/// Pick which computed result rows appear in UI (audio is separate).
class ResultFieldsScreen extends StatelessWidget {
  const ResultFieldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dragy = context.watch<DragyProvider>();
    final fields = VisibleResultField.values.where((f) {
      if (dragy.isMetric && f.isImperialOnly) return false;
      if (!dragy.isMetric && f.isMetricOnly) return false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Result fields',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Everything is still calculated and saved. Only enabled fields '
              'show on the dashboard, run detail, and Android Auto.',
              style: GoogleFonts.roboto(
                color: Colors.white54,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'DISPLAY',
              style: GoogleFonts.roboto(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
          for (final f in fields)
            _FieldTile(
              field: f,
              enabled: dragy.isResultFieldVisible(f),
              onChanged: (v) => dragy.setResultFieldVisible(f, v),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final VisibleResultField field;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _FieldTile({
    required this.field,
    required this.enabled,
    required this.onChanged,
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
        title: Text(
          field.label,
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          enabled ? 'Shown in results' : 'Hidden (still computed)',
          style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
        ),
        value: enabled,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFF42A5F5),
        activeTrackColor: const Color(0xFF1565C0),
        inactiveThumbColor: Colors.white38,
        inactiveTrackColor: Colors.white12,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

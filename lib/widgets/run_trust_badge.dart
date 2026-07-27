import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/run_trust.dart';

/// Compact green/amber/red trust chip for history and run detail.
class RunTrustBadge extends StatelessWidget {
  final RunTrust trust;
  final bool compact;

  const RunTrustBadge({
    super.key,
    required this.trust,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(trust.colorArgb);
    final subtitle = _subtitle(trust);

    return Tooltip(
      message: _tooltip(trust),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              trust.level == RunTrustLevel.high
                  ? Icons.verified_outlined
                  : trust.level == RunTrustLevel.medium
                      ? Icons.shield_outlined
                      : trust.level == RunTrustLevel.low
                          ? Icons.gpp_maybe_outlined
                          : Icons.help_outline,
              size: compact ? 13 : 15,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              compact
                  ? trust.shortLabel
                  : '${trust.shortLabel}${subtitle == null ? '' : ' · $subtitle'}',
              style: GoogleFonts.roboto(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _subtitle(RunTrust t) {
    if (t.avgHAccM == null) return null;
    return '±${t.avgHAccM!.toStringAsFixed(1)} m';
  }

  static String _tooltip(RunTrust t) {
    final parts = <String>[];
    if (t.usedPvt == true) {
      parts.add('NAV-PVT');
    } else if (t.usedPvt == false) {
      parts.add('NMEA / mixed');
    }
    if (t.avgHAccM != null) {
      parts.add('avg hAcc ${t.avgHAccM!.toStringAsFixed(2)} m');
    }
    if (t.minHAccM != null) {
      parts.add('min hAcc ${t.minHAccM!.toStringAsFixed(2)} m');
    }
    if (t.maxSAccMps != null) {
      parts.add('max sAcc ${(t.maxSAccMps! * 3.6).toStringAsFixed(1)} km/h');
    }
    if (t.avgNumSV != null) {
      parts.add('avg ${t.avgNumSV!.toStringAsFixed(0)} SV');
    }
    if (parts.isEmpty) return 'No GPS trust data for this run';
    return parts.join(' · ');
  }
}

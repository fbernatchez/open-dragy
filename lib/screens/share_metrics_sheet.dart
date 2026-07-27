import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/run_share_service.dart';

/// Bottom sheet: pick which metrics go on the share PNG (max [ShareSelection.maxMetrics]).
Future<ShareSelection?> showShareMetricsPicker({
  required BuildContext context,
  required List<ShareMetricCandidate> candidates,
  required String? preferredPrimaryId,
}) {
  return showModalBottomSheet<ShareSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _ShareMetricsSheet(
      candidates: candidates,
      preferredPrimaryId: preferredPrimaryId,
    ),
  );
}

class _ShareMetricsSheet extends StatefulWidget {
  final List<ShareMetricCandidate> candidates;
  final String? preferredPrimaryId;

  const _ShareMetricsSheet({
    required this.candidates,
    required this.preferredPrimaryId,
  });

  @override
  State<_ShareMetricsSheet> createState() => _ShareMetricsSheetState();
}

class _ShareMetricsSheetState extends State<_ShareMetricsSheet> {
  late final Set<String> _selected;
  late String? _primaryId;
  bool _includeChart = true;

  @override
  void initState() {
    super.initState();
    _selected = defaultShareSelectionIds(
      candidates: widget.candidates,
      preferredPrimaryId: widget.preferredPrimaryId,
    );
    _primaryId = resolveSharePrimaryId(
      selectedIds: _selected,
      preferredPrimaryId: widget.preferredPrimaryId,
      candidates: widget.candidates,
    );
  }

  void _toggle(String id, bool enable) {
    setState(() {
      if (enable) {
        if (_selected.length >= ShareSelection.maxMetrics) return;
        _selected.add(id);
      } else {
        _selected.remove(id);
        if (_primaryId == id) {
          _primaryId = resolveSharePrimaryId(
            selectedIds: _selected,
            preferredPrimaryId: widget.preferredPrimaryId,
            candidates: widget.candidates,
          );
        }
      }
      if (_primaryId == null || !_selected.contains(_primaryId)) {
        _primaryId = resolveSharePrimaryId(
          selectedIds: _selected,
          preferredPrimaryId: widget.preferredPrimaryId,
          candidates: widget.candidates,
        );
      }
    });
  }

  void _setPrimary(String id) {
    setState(() {
      if (!_selected.contains(id)) {
        if (_selected.length >= ShareSelection.maxMetrics) {
          // Swap: drop last non-primary to make room.
          final drop = _selected.firstWhere(
            (e) => e != _primaryId,
            orElse: () => id,
          );
          if (drop != id) _selected.remove(drop);
        }
        _selected.add(id);
      }
      _primaryId = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    final atCap = _selected.length >= ShareSelection.maxMetrics;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share run',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pick up to ${ShareSelection.maxMetrics} metrics · '
                          'tap star for the big headline time',
                          style: GoogleFonts.roboto(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_selected.length}/${ShareSelection.maxMetrics}',
                    style: GoogleFonts.robotoMono(
                      color: atCap
                          ? const Color(0xFFFFBF00)
                          : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No shareable metrics on this run.',
                  style: GoogleFonts.roboto(color: Colors.white54),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  itemCount: widget.candidates.length,
                  itemBuilder: (context, i) {
                    final c = widget.candidates[i];
                    final checked = _selected.contains(c.id);
                    final isPrimary = _primaryId == c.id;
                    final lockedOut = atCap && !checked;

                    return Opacity(
                      opacity: lockedOut ? 0.45 : 1,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: checked
                              ? const Color(0xFF1A1A1A)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPrimary
                                ? const Color(0xFFFFBF00).withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: checked,
                          onChanged: lockedOut
                              ? null
                              : (v) => _toggle(c.id, v ?? false),
                          activeColor: const Color(0xFF1565C0),
                          checkColor: Colors.white,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.only(
                            left: 4,
                            right: 8,
                          ),
                          title: Text(
                            c.label,
                            style: GoogleFonts.roboto(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            c.trapText != null
                                ? '${c.timeText}  @ ${c.trapText}'
                                : c.timeText,
                            style: GoogleFonts.robotoMono(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          secondary: IconButton(
                            tooltip: 'Headline',
                            onPressed: () => _setPrimary(c.id),
                            icon: Icon(
                              isPrimary ? Icons.star : Icons.star_border,
                              color: isPrimary
                                  ? const Color(0xFFFFBF00)
                                  : Colors.white30,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SwitchListTile(
                value: _includeChart,
                onChanged: (v) => setState(() => _includeChart = v),
                activeThumbColor: const Color(0xFF42A5F5),
                activeTrackColor: const Color(0xFF1565C0),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Include telemetry chart',
                  style: GoogleFonts.roboto(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Speed + G on the share image',
                  style: GoogleFonts.roboto(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty || _primaryId == null
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                                ShareSelection(
                                  primaryId: _primaryId!,
                                  selectedIds: List<String>.from(_selected),
                                  includeChart: _includeChart,
                                ),
                              );
                            },
                      icon: const Icon(Icons.share),
                      label: const Text('Create PNG'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                        minimumSize: const Size.fromHeight(48),
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
  }
}

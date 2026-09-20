import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';

class BoxPivotDialog extends StatelessWidget {
  const BoxPivotDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BoxPivotPreviewWidget(isDialogMode: true),
            ],
          ),
        ),
      ),
    );
  }
}

class BoxPivotPreviewWidget extends StatelessWidget {
  final bool isDialogMode;

  const BoxPivotPreviewWidget({
    super.key,
    this.isDialogMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final dragy = Provider.of<DragyProvider>(context);
    final angle = dragy.boxPivotAngle;

    return Container(
      padding: isDialogMode ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: isDialogMode
          ? null
          : BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: Color(0xFF42A5F5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Box Pivot Orientation',
                      style: GoogleFonts.roboto(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Set mounting orientation',
                      style: GoogleFonts.roboto(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '$angle°',
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFF90CAF9),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isDialogMode) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),

          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF1565C0).withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                    ),
                  ),

                  CustomPaint(
                    size: const Size(220, 220),
                    painter: _CrosshairPainter(),
                  ),

                  Positioned(
                    top: 6,
                    child: Text(
                      'FRONT',
                      style: GoogleFonts.roboto(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 6,
                    child: Text(
                      'BACK',
                      style: GoogleFonts.roboto(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  Positioned(
                    left: 6,
                    child: Text(
                      'LEFT',
                      style: GoogleFonts.roboto(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  Positioned(
                    right: 6,
                    child: Text(
                      'RIGHT',
                      style: GoogleFonts.roboto(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),

                  Transform.rotate(
                    angle: angle * (pi / 180.0),
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2196F3).withValues(alpha: 0.2),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/box-top-view.png',
                        width: 120,
                        height: 70,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetChip(
                label: '0°',
                isSelected: angle == 0,
                onTap: () => dragy.setBoxPivotAngle(0),
              ),
              _buildPresetChip(
                label: '90°',
                isSelected: angle == 90,
                onTap: () => dragy.setBoxPivotAngle(90),
              ),
              _buildPresetChip(
                label: '180°',
                isSelected: angle == 180,
                onTap: () => dragy.setBoxPivotAngle(180),
              ),
              _buildPresetChip(
                label: '270°',
                isSelected: angle == 270,
                onTap: () => dragy.setBoxPivotAngle(270),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white54, size: 22),
                tooltip: '-1 Degree',
                onPressed: () => dragy.setBoxPivotAngle((angle - 1 + 360) % 360),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: const Color(0xFF1E88E5),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFF42A5F5),
                    overlayColor: const Color(0xFF2196F3).withValues(alpha: 0.2),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: angle.toDouble(),
                    min: 0,
                    max: 359,
                    onChanged: (val) => dragy.setBoxPivotAngle(val.round()),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white54, size: 22),
                tooltip: '+1 Degree',
                onPressed: () => dragy.setBoxPivotAngle((angle + 1) % 360),
              ),
            ],
          ),


          if (isDialogMode) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF42A5F5)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.roboto(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawLine(
      Offset(center.dx, 16),
      Offset(center.dx, size.height - 16),
      paint,
    );

    canvas.drawLine(
      Offset(16, center.dy),
      Offset(size.width - 16, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dragy_provider.dart';
import '../theme/app_theme.dart';

class BoxPivotDialog extends StatelessWidget {
  const BoxPivotDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.cardBorder),
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
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      padding: isDialogMode ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: isDialogMode
          ? null
          : BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
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
                  color: colors.accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.explore_outlined,
                  color: colors.accent,
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
                      style: AppTheme.font(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Set mounting orientation',
                      style: AppTheme.font(
                        color: colors.textMuted,
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
                  color: colors.accent.withValues(alpha: isDark ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '$angle°',
                  style: AppTheme.numericFont(
                    color: colors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isDialogMode) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, color: colors.textMuted, size: 20),
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
                          colors.accent.withValues(alpha: isDark ? 0.08 : 0.04),
                          Colors.transparent,
                        ],
                      ),
                      border: Border.all(
                        color: colors.cardBorder,
                        width: 1.5,
                      ),
                    ),
                  ),

                  CustomPaint(
                    size: const Size(220, 220),
                    painter: _CrosshairPainter(isDark: isDark),
                  ),

                  Positioned(
                    top: 6,
                    child: Text(
                      'FRONT',
                      style: AppTheme.font(
                        color: colors.textMuted,
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
                      style: AppTheme.font(
                        color: colors.textMuted,
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
                      style: AppTheme.font(
                        color: colors.textMuted,
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
                      style: AppTheme.font(
                        color: colors.textMuted,
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
                            color: colors.accent.withValues(alpha: isDark ? 0.2 : 0.15),
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
                context: context,
                label: '0°',
                isSelected: angle == 0,
                onTap: () => dragy.setBoxPivotAngle(0),
              ),
              _buildPresetChip(
                context: context,
                label: '90°',
                isSelected: angle == 90,
                onTap: () => dragy.setBoxPivotAngle(90),
              ),
              _buildPresetChip(
                context: context,
                label: '180°',
                isSelected: angle == 180,
                onTap: () => dragy.setBoxPivotAngle(180),
              ),
              _buildPresetChip(
                context: context,
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
                icon: Icon(Icons.remove_circle_outline,
                    color: colors.textMuted, size: 22),
                tooltip: '-1 Degree',
                onPressed: () => dragy.setBoxPivotAngle((angle - 1 + 360) % 360),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                    thumbColor: colors.accent,
                    overlayColor: colors.accent.withValues(alpha: 0.2),
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
                icon: Icon(Icons.add_circle_outline,
                    color: colors.textMuted, size: 22),
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
                  backgroundColor: colors.accent,
                  foregroundColor: colors.buttonForeground,
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
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent
              : colors.subtleBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colors.accent
                : colors.cardBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.font(
            color: isSelected ? colors.buttonForeground : colors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final bool isDark;

  _CrosshairPainter({this.isDark = true});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)
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
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

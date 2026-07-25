import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_cues.dart';

/// Full-screen finish cue — flash or checkered flag. Self-dismisses.
class FinishCelebrationOverlay extends StatefulWidget {
  final FinishCelebrationMode mode;

  const FinishCelebrationOverlay({
    super.key,
    required this.mode,
  });

  @override
  State<FinishCelebrationOverlay> createState() =>
      _FinishCelebrationOverlayState();
}

class _FinishCelebrationOverlayState extends State<FinishCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final isFlash = widget.mode == FinishCelebrationMode.flash;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: isFlash ? 900 : 1600),
    );
    _opacity = isFlash
        ? TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0, end: 0.85), weight: 1),
            TweenSequenceItem(tween: Tween(begin: 0.85, end: 0), weight: 1),
            TweenSequenceItem(tween: Tween(begin: 0, end: 0.7), weight: 1),
            TweenSequenceItem(tween: Tween(begin: 0.7, end: 0), weight: 1),
            TweenSequenceItem(tween: Tween(begin: 0, end: 0.55), weight: 1),
            TweenSequenceItem(tween: Tween(begin: 0.55, end: 0), weight: 1),
          ]).animate(_controller)
        : TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
            TweenSequenceItem(tween: ConstantTween(1), weight: 2.2),
            TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1.2),
          ]).animate(CurvedAnimation(
            parent: _controller,
            curve: Curves.easeInOut,
          ));
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done || widget.mode == FinishCelebrationMode.off) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, _) {
          if (widget.mode == FinishCelebrationMode.flash) {
            return Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: const ColoredBox(color: Colors.white),
            );
          }

          return Opacity(
            opacity: _opacity.value.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const CustomPaint(painter: _CheckeredPainter()),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                    child: Text(
                      'FINISH',
                      style: GoogleFonts.robotoMono(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CheckeredPainter extends CustomPainter {
  const _CheckeredPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 8;
    final cellW = size.width / cells;
    final cellH = size.height / cells;
    final black = Paint()..color = Colors.black;
    final white = Paint()..color = Colors.white;

    for (var row = 0; row < cells; row++) {
      for (var col = 0; col < cells; col++) {
        final paint = ((row + col).isEven) ? black : white;
        canvas.drawRect(
          Rect.fromLTWH(col * cellW, row * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

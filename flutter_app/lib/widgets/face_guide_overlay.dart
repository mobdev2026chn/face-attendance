import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Professional biometric face-scan guide: a glowing oval ring with corner
/// focus brackets and an animated scan line that sweeps across the face.
/// Shows a polished success badge once recognition passes.
class FaceGuideOverlay extends StatefulWidget {
  final Color color;
  final bool showSuccessTick;

  const FaceGuideOverlay({super.key, required this.color, this.showSuccessTick = false});

  @override
  State<FaceGuideOverlay> createState() => _FaceGuideOverlayState();
}

class _FaceGuideOverlayState extends State<FaceGuideOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fill the available area (almost the whole screen). Falls back to MediaQuery
    // when given unbounded constraints.
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.of(context).size;
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : screen.width;
        final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : screen.height * 0.7;
        final w = maxW * 0.98;
        final h = maxH * 0.98;
        final guideSize = Size(w, h);
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value; // oscillates 0 -> 1 -> 0
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: guideSize,
                      painter: _FaceGuidePainter(
                        color: widget.color,
                        sweep: t,
                        glow: 0.55 + 0.45 * t,
                        showScanLine: !widget.showSuccessTick,
                      ),
                    ),
                    if (widget.showSuccessTick) const _SuccessBadge(),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final Color color;
  final double sweep; // 0..1 vertical position of the scan line
  final double glow; // 0..1 glow intensity
  final bool showScanLine;

  _FaceGuidePainter({
    required this.color,
    required this.sweep,
    required this.glow,
    required this.showScanLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.9,
      height: size.height * 0.92,
    );

    // Soft outer glow.
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.22 * glow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawOval(ovalRect, glowPaint);

    // Crisp guide ring (thin border).
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(ovalRect, ringPaint);

    // Corner focus brackets, sitting just outside the oval bounding box.
    _drawCorners(canvas, ovalRect.inflate(12));

    // Animated scan line, clipped to the oval so it traces the face.
    if (showScanLine) {
      canvas.save();
      canvas.clipPath(Path()..addOval(ovalRect));

      final y = ovalRect.top + ovalRect.height * sweep;
      const band = 30.0;
      final bandRect = Rect.fromLTWH(ovalRect.left, y - band / 2, ovalRect.width, band);
      final bandPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, bandRect.top),
          Offset(0, bandRect.bottom),
          [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.0),
          ],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawRect(bandRect, bandPaint);

      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(ovalRect.left, y), Offset(ovalRect.right, y), linePaint);

      canvas.restore();
    }
  }

  void _drawCorners(Canvas canvas, Rect r) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const len = 26.0;

    // Top-left.
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(len, 0), p);
    canvas.drawLine(r.topLeft, r.topLeft + const Offset(0, len), p);
    // Top-right.
    canvas.drawLine(r.topRight, r.topRight + const Offset(-len, 0), p);
    canvas.drawLine(r.topRight, r.topRight + const Offset(0, len), p);
    // Bottom-left.
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), p);
    canvas.drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), p);
    // Bottom-right.
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), p);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), p);
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) =>
      old.sweep != sweep ||
      old.glow != glow ||
      old.color != color ||
      old.showScanLine != showScanLine;
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: green,
          boxShadow: [
            BoxShadow(color: green.withValues(alpha: 0.5), blurRadius: 24, spreadRadius: 2),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 50),
      ),
    );
  }
}

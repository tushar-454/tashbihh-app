import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tasbih_theme.dart';
import '../../core/models/app_state.dart';

class CounterRing extends CustomPainter {
  CounterRing({required this.count, required this.target, required this.style});
  final double count;
  final int target;
  final CounterStyle style;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 320);
    const center = Offset(160, 160);
    final track = hsl(220, 12, 18);
    if (style == CounterStyle.classic) {
      final radius = target <= 34
          ? 5.0
          : target <= 50
          ? 4.0
          : 3.0;
      for (var i = 0; i < target; i++) {
        final angle = i / target * math.pi * 2 - math.pi / 2;
        canvas.drawCircle(
          center + Offset(130 * math.cos(angle), 130 * math.sin(angle)),
          radius,
          Paint()..color = i < count ? hsl(i / target * 360, 80, 60) : track,
        );
      }
    } else {
      final rect = Rect.fromCircle(center: center, radius: 118);
      canvas.drawCircle(
        center,
        118,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16,
      );
      final sweep = (count / target).clamp(0.0, 1.0) * math.pi * 2;
      if (sweep > 0) {
        final paint = Paint()
          ..color = hsl(42, 62, 52)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          rect,
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..color = hsl(42, 62, 52, .38)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CounterRing oldDelegate) =>
      count != oldDelegate.count ||
      target != oldDelegate.target ||
      style != oldDelegate.style;
}

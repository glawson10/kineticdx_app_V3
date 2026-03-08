import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../data/body_chart.dart';

/// CustomPainter that renders body chart strokes on top of a background image.
class BodyChartPainter extends CustomPainter {
  final ui.Image? backgroundImage;
  final List<BodyChartStroke> strokes;
  final BodyChartStroke? currentStroke; // stroke being drawn

  const BodyChartPainter({
    required this.backgroundImage,
    required this.strokes,
    this.currentStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) Draw background image (body chart PNG)
    if (backgroundImage != null) {
      final srcRect = Rect.fromLTWH(
        0,
        0,
        backgroundImage!.width.toDouble(),
        backgroundImage!.height.toDouble(),
      );
      final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(
        backgroundImage!,
        srcRect,
        dstRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // 2) Draw all completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, size, stroke);
    }

    // 3) Draw current stroke (being drawn)
    if (currentStroke != null && currentStroke!.points.isNotEmpty) {
      _drawStroke(canvas, size, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, Size size, BodyChartStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = Color(stroke.type.colorValue)
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Dashed pattern for pins & needles: Flutter Canvas has no PathEffect,
    // so dashing is handled in _drawDashedPath below.
    final dashed = stroke.type.isDashed;

    final path = Path();

    // Convert normalized coordinates to canvas coordinates
    for (int i = 0; i < stroke.points.length; i++) {
      final point = stroke.points[i];
      final x = point.xNorm * size.width;
      final y = point.yNorm * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (dashed) {
      _drawDashedPath(canvas, path, paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  /// Draws [path] as a dashed line (6 px on, 4 px off).
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashLen = 6;
    const double gapLen = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLen).clamp(0.0, metric.length);
        final segment = metric.extractPath(distance, end);
        canvas.drawPath(segment, paint);
        distance = end + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(BodyChartPainter oldDelegate) {
    return oldDelegate.backgroundImage != backgroundImage ||
        oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke;
  }
}

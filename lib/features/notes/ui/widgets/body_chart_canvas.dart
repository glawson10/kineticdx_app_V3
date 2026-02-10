import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/body_chart.dart';
import 'body_chart_painter.dart';

/// Canvas widget for drawing on a single body chart side (front or back).
///
/// Handles:
/// - Gesture detection (pan to draw)
/// - Coordinate normalization (0..1)
/// - Stroke creation with current symptom type
class BodyChartCanvas extends StatefulWidget {
  final String assetPath;
  final List<BodyChartStroke> strokes;
  final SymptomType currentSymptomType;
  final double strokeWidth;
  final ValueChanged<List<BodyChartStroke>> onStrokesChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;

  const BodyChartCanvas({
    super.key,
    required this.assetPath,
    required this.strokes,
    required this.currentSymptomType,
    required this.strokeWidth,
    required this.onStrokesChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
  });

  @override
  State<BodyChartCanvas> createState() => _BodyChartCanvasState();
}

class _BodyChartCanvasState extends State<BodyChartCanvas> {
  ui.Image? _backgroundImage;
  BodyChartStroke? _currentStroke;
  int _nextPointIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(BodyChartCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load(widget.assetPath);
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _backgroundImage = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          onPanStart: (details) => _onPanStart(details, width, height),
          onPanUpdate: (details) => _onPanUpdate(details, width, height),
          onPanEnd: (details) => _onPanEnd(),
          child: CustomPaint(
            size: Size(width, height),
            painter: BodyChartPainter(
              backgroundImage: _backgroundImage,
              strokes: widget.strokes,
              currentStroke: _currentStroke,
            ),
          ),
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details, double width, double height) {
    widget.onInteractionStart?.call();

    final localPos = details.localPosition;
    final xNorm = (localPos.dx / width).clamp(0.0, 1.0);
    final yNorm = (localPos.dy / height).clamp(0.0, 1.0);

    _nextPointIndex = 0;
    _currentStroke = BodyChartStroke(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: widget.currentSymptomType,
      width: widget.strokeWidth,
      points: [
        BodyChartStrokePoint(
          xNorm: xNorm,
          yNorm: yNorm,
          t: _nextPointIndex.toDouble(),
        ),
      ],
    );

    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details, double width, double height) {
    if (_currentStroke == null) return;

    final localPos = details.localPosition;
    final xNorm = (localPos.dx / width).clamp(0.0, 1.0);
    final yNorm = (localPos.dy / height).clamp(0.0, 1.0);

    _nextPointIndex++;
    final updatedPoints = List<BodyChartStrokePoint>.from(_currentStroke!.points)
      ..add(
        BodyChartStrokePoint(
          xNorm: xNorm,
          yNorm: yNorm,
          t: _nextPointIndex.toDouble(),
        ),
      );

    _currentStroke = BodyChartStroke(
      id: _currentStroke!.id,
      type: _currentStroke!.type,
      width: _currentStroke!.width,
      points: updatedPoints,
    );

    setState(() {});
  }

  void _onPanEnd() {
    if (_currentStroke != null && _currentStroke!.points.isNotEmpty) {
      final updatedStrokes = List<BodyChartStroke>.from(widget.strokes)
        ..add(_currentStroke!);
      widget.onStrokesChanged(updatedStrokes);
    }

    _currentStroke = null;
    _nextPointIndex = 0;
    widget.onInteractionEnd?.call();

    setState(() {});
  }

  @override
  void dispose() {
    _backgroundImage?.dispose();
    super.dispose();
  }
}

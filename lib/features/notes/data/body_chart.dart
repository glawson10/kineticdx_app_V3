/// Body chart drawing data models for clinical notes.
///
/// Stores strokes as normalized vectors (not rasterized) to support:
/// - Clean scaling across devices
/// - Editability
/// - Export to PDF with high quality

enum BodyChartSide { front, back }

enum SymptomType { pain, stiffness, numbness, pinsNeedles }

/// Extension to provide UI-friendly labels and colors for symptom types.
extension SymptomTypeExt on SymptomType {
  String get label {
    switch (this) {
      case SymptomType.pain:
        return 'Pain';
      case SymptomType.stiffness:
        return 'Stiffness';
      case SymptomType.numbness:
        return 'Numbness';
      case SymptomType.pinsNeedles:
        return 'Pins & needles';
    }
  }

  /// Color for rendering this symptom type (muted for clinical feel).
  int get colorValue {
    switch (this) {
      case SymptomType.pain:
        return 0xFFD32F2F; // Muted red
      case SymptomType.stiffness:
        return 0xFF1976D2; // Muted blue
      case SymptomType.numbness:
        return 0xFFFBC02D; // Muted yellow
      case SymptomType.pinsNeedles:
        return 0xFF7B1FA2; // Muted purple
    }
  }

  /// Stroke width for this symptom type (clinical differentiation).
  double get strokeWidth {
    switch (this) {
      case SymptomType.pain:
        return 5.0; // Medium
      case SymptomType.stiffness:
        return 7.0; // Thick
      case SymptomType.numbness:
        return 3.0; // Thin
      case SymptomType.pinsNeedles:
        return 4.0; // Medium-thin (will be dotted)
    }
  }

  /// Whether this symptom type should be drawn with a dotted/dashed pattern.
  bool get isDashed {
    return this == SymptomType.pinsNeedles;
  }
}

/// A single point in a stroke, stored as normalized coordinates (0..1).
class BodyChartStrokePoint {
  /// Normalized x coordinate (0..1) relative to image width.
  final double xNorm;

  /// Normalized y coordinate (0..1) relative to image height.
  final double yNorm;

  /// Timestamp or progressive index (used for stroke ordering).
  final double t;

  const BodyChartStrokePoint({
    required this.xNorm,
    required this.yNorm,
    required this.t,
  });

  Map<String, dynamic> toMap() => {
        'x': xNorm,
        'y': yNorm,
        't': t,
      };

  factory BodyChartStrokePoint.fromMap(Map<String, dynamic> m) {
    return BodyChartStrokePoint(
      xNorm: (m['x'] as num?)?.toDouble() ?? 0.0,
      yNorm: (m['y'] as num?)?.toDouble() ?? 0.0,
      t: (m['t'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// A single stroke (continuous drawing gesture) on the body chart.
class BodyChartStroke {
  final String id;
  final SymptomType type;
  final double width; // stroke width in logical px (base width)
  final List<BodyChartStrokePoint> points;

  const BodyChartStroke({
    required this.id,
    required this.type,
    required this.width,
    required this.points,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'width': width,
        'points': points.map((p) => p.toMap()).toList(),
      };

  factory BodyChartStroke.fromMap(Map<String, dynamic> m) {
    final typeStr = (m['type'] ?? 'pain').toString();
    SymptomType type;
    try {
      type = SymptomType.values.firstWhere((e) => e.name == typeStr);
    } catch (_) {
      type = SymptomType.pain;
    }

    return BodyChartStroke(
      id: (m['id'] ?? '').toString(),
      type: type,
      width: (m['width'] as num?)?.toDouble() ?? 4.0,
      points: ((m['points'] as List<dynamic>? ?? const []))
          .map((e) => BodyChartStrokePoint.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Complete body chart state (front + back strokes).
class BodyChartState {
  final List<BodyChartStroke> frontStrokes;
  final List<BodyChartStroke> backStrokes;

  const BodyChartState({
    required this.frontStrokes,
    required this.backStrokes,
  });

  /// Empty state with no strokes.
  const BodyChartState.empty()
      : frontStrokes = const [],
        backStrokes = const [];

  /// Returns true if both front and back have no strokes.
  bool get isEmpty => frontStrokes.isEmpty && backStrokes.isEmpty;

  Map<String, dynamic> toMap() => {
        'front': frontStrokes.map((s) => s.toMap()).toList(),
        'back': backStrokes.map((s) => s.toMap()).toList(),
      };

  factory BodyChartState.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BodyChartState.empty();

    return BodyChartState(
      frontStrokes: ((m['front'] as List<dynamic>? ?? const []))
          .map((e) => BodyChartStroke.fromMap(e as Map<String, dynamic>))
          .toList(),
      backStrokes: ((m['back'] as List<dynamic>? ?? const []))
          .map((e) => BodyChartStroke.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Creates a new state with updated front strokes.
  BodyChartState copyWithFront(List<BodyChartStroke> newFront) {
    return BodyChartState(
      frontStrokes: newFront,
      backStrokes: backStrokes,
    );
  }

  /// Creates a new state with updated back strokes.
  BodyChartState copyWithBack(List<BodyChartStroke> newBack) {
    return BodyChartState(
      frontStrokes: frontStrokes,
      backStrokes: newBack,
    );
  }
}

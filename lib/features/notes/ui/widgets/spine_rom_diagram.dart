// Spine range-of-motion diagram: radial axes with draggable markers.
// Used for cervical, thoracic, and lumbar AROM/PROM documentation.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/region_objective_templates.dart';
import '../../../../models/soap_note.dart';

/// One axis in the diagram: angle (radians from right, clockwise), label, movement key.
class _SpineAxis {
  final double angleRad;
  final String label;
  final List<String> movementNames; // possible template names for this axis

  const _SpineAxis({
    required this.angleRad,
    required this.label,
    required this.movementNames,
  });
}

const List<_SpineAxis> _spineAxes = [
  _SpineAxis(angleRad: -math.pi / 2, label: 'Flexion', movementNames: ['Flexion']),
  _SpineAxis(angleRad: math.pi / 2, label: 'Extension', movementNames: ['Extension']),
  _SpineAxis(angleRad: math.pi, label: 'L lateral flex', movementNames: ['Lateral Flexion Left', 'Side-flexion Left']),
  _SpineAxis(angleRad: 0, label: 'R lateral flex', movementNames: ['Lateral Flexion Right', 'Side-flexion Right']),
  _SpineAxis(angleRad: -3 * math.pi / 4, label: 'L rotation', movementNames: ['Rotation Left']),
  _SpineAxis(angleRad: -math.pi / 4, label: 'R rotation', movementNames: ['Rotation Right']),
];

/// Returns the RomMovementDef and RomFinding for an axis by matching movement name.
void _axisMatch(
  List<RomMovementDef> defs,
  List<RomFinding> findings,
  _SpineAxis axis,
  void Function(RomMovementDef def, RomFinding finding) onMatch,
) {
  for (final name in axis.movementNames) {
    final def = defs.cast<RomMovementDef?>().firstWhere(
          (d) => d?.movement == name,
          orElse: () => null,
        );
    if (def != null) {
      final finding = findings.cast<RomFinding?>().firstWhere(
            (f) => f?.movement == def.movement,
            orElse: () => null,
          );
      if (finding != null) {
        onMatch(def, finding);
        return;
      }
    }
  }
}

class SpineRomDiagram extends StatefulWidget {
  final List<RomMovementDef> defs;
  final List<RomFinding> findings;
  final bool readOnly;
  final ValueChanged<List<RomFinding>> onUpdate;

  const SpineRomDiagram({
    super.key,
    required this.defs,
    required this.findings,
    required this.readOnly,
    required this.onUpdate,
  });

  @override
  State<SpineRomDiagram> createState() => _SpineRomDiagramState();
}

class _SpineRomDiagramState extends State<SpineRomDiagram> {
  static const double _radius = 100;
  static const double _centerRadius = 6;
  static const double _axisHitSlop = 6;   // tap on main axis = set ROM value (narrow so pain line is easy to tap)
  static const double _painLineOffset = 10; // grey/red pain line offset to left of axis
  static const double _painHitWidth = 14;   // tap within this width of pain line = set pain

  int? _draggingAxisIndex;

  /// Updates only diagram ROM (diagramValue); does not touch value/valueUnit (list inputs).
  List<RomFinding> _mergeUpdateDiagramOnly(String movement, double diagramValue) {
    final byMovement = {for (final f in widget.findings) f.movement: f};
    final existing = byMovement[movement];
    byMovement[movement] = (existing ?? RomFinding(movement: movement))
        .copyWith(diagramValue: diagramValue);
    return widget.defs
        .map((d) => byMovement[d.movement] ?? RomFinding(movement: d.movement))
        .toList();
  }

  /// Two-tap pain segment: first tap sets painFrom, second tap on same axis sets painTo.
  void _setPainSegmentForAxis(int axisIndex, double normalizedDistance) {
    RomMovementDef? def;
    RomFinding? finding;
    _axisMatch(widget.defs, widget.findings, _spineAxes[axisIndex], (d, f) {
      def = d;
      finding = f;
    });
    if (def == null || finding == null) return;
    final maxVal = (def!.maxDeg > 0 ? def!.maxDeg : 100).toDouble();
    final val = (normalizedDistance * maxVal).roundToDouble().clamp(0.0, maxVal);
    final byMovement = {for (final f in widget.findings) f.movement: f};
    double? from = finding!.painFrom;
    double? to = finding!.painTo;
    if (from != null && to == null) {
      to = val;
      if (from > to) { final t = from; from = to; to = t; }
    } else {
      from = val;
      to = null;
    }
    byMovement[def!.movement] = finding!.copyWith(
        painful: true, painFrom: from, painTo: to, painAt: null);
    widget.onUpdate(widget.defs
        .map((d) => byMovement[d.movement] ?? RomFinding(movement: d.movement))
        .toList());
  }

  void _setValueForAxis(int axisIndex, double normalizedDistance) {
    RomMovementDef? def;
    RomFinding? finding;
    _axisMatch(widget.defs, widget.findings, _spineAxes[axisIndex], (d, f) {
      def = d;
      finding = f;
    });
    final defVal = def;
    final findingVal = finding;
    if (defVal == null || findingVal == null) return;
    final maxVal = (defVal.maxDeg > 0 ? defVal.maxDeg : 100).toDouble();
    final diagramVal = (normalizedDistance * maxVal).roundToDouble().clamp(0.0, maxVal);
    // Diagram is independent of list degree/% – only set diagramValue
    widget.onUpdate(_mergeUpdateDiagramOnly(defVal.movement, diagramVal));
  }

  @override
  Widget build(BuildContext context) {
    const padding = 12.0;
    final diagramSize = _radius * 2 + padding * 2;
    final hintHeight = widget.readOnly ? 0.0 : 40.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: diagramSize,
        height: diagramSize + hintHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cx = diagramSize / 2;
            final cy = diagramSize / 2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: diagramSize,
                  height: diagramSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(diagramSize, diagramSize),
                        painter: _SpineRomPainter(
                          center: Offset(cx, cy),
                          radius: _radius,
                          defs: widget.defs,
                          findings: widget.findings,
                        ),
                      ),
                      if (!widget.readOnly)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) {
                              final axis = _hitTestAxis(d.localPosition, cx, cy);
                              if (axis != null) {
                                setState(() => _draggingAxisIndex = axis);
                                _updateFromPosition(d.localPosition, cx, cy, axis, setPain: false);
                              }
                            },
                            onPanUpdate: (d) {
                              if (_draggingAxisIndex != null) {
                                _updateFromPosition(d.localPosition, cx, cy, _draggingAxisIndex!, setPain: false);
                              }
                            },
                    onPanEnd: (_) => setState(() => _draggingAxisIndex = null),
                    onTapUp: (d) {
                      final result = _hitTestTap(d.localPosition, cx, cy);
                      if (result != null) {
                        final (axisIndex, setPain) = result;
                        _updateFromPosition(d.localPosition, cx, cy, axisIndex, setPain: setPain);
                      }
                    },
                          ),
                        ),
                    ],
                  ),
                ),
                if (!widget.readOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                    child: Text(
                      'Tap main line = set ROM. Tap grey line: 1st tap = start of pain section, 2nd tap = end.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Hit test for pan (drag): only main axis, any perpendicular distance within slop.
  int? _hitTestAxis(Offset local, double cx, double cy) {
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    if (dx * dx + dy * dy < _centerRadius * _centerRadius) return null;
    int best = -1;
    double bestPerp = double.infinity;
    for (var i = 0; i < _spineAxes.length; i++) {
      final a = _spineAxes[i].angleRad;
      final ax = math.cos(a);
      final ay = math.sin(a);
      final projection = dx * ax + dy * ay;
      if (projection < 0) continue;
      final perpX = dx - ax * projection;
      final perpY = dy - ay * projection;
      final perpDist = math.sqrt(perpX * perpX + perpY * perpY);
      if (perpDist < _axisHitSlop && perpDist < bestPerp) {
        bestPerp = perpDist;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  /// Tap: return (axisIndex, setPain). Pain zone = grey line (left of axis). Value zone = on main axis.
  (int, bool)? _hitTestTap(Offset local, double cx, double cy) {
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    if (dx * dx + dy * dy < _centerRadius * _centerRadius) return null;
    int bestAxis = -1;
    double bestScore = double.infinity;
    bool bestIsPain = false;
    for (var i = 0; i < _spineAxes.length; i++) {
      final a = _spineAxes[i].angleRad;
      final ax = math.cos(a);
      final ay = math.sin(a);
      final projection = dx * ax + dy * ay;
      if (projection < 0) continue;
      final perpX = dx - ax * projection;
      final perpY = dy - ay * projection;
      final perpDist = math.sqrt(perpX * perpX + perpY * perpY);
      final leftDir = -math.sin(a) * perpX + math.cos(a) * perpY;
      final onLeft = leftDir > 0;
      // Value zone: on main axis (perpDist 0..8) – tap sets ROM
      if (perpDist <= _axisHitSlop) {
        if (perpDist < bestScore) {
          bestScore = perpDist;
          bestAxis = i;
          bestIsPain = false;
        }
      }
      // Pain zone: left side only, perpDist 6..24 (grey line) – tap sets pain
      if (onLeft && perpDist >= _axisHitSlop && perpDist <= _painLineOffset + _painHitWidth) {
        final score = (perpDist - _painLineOffset).abs();
        if (score < bestScore) {
          bestScore = score;
          bestAxis = i;
          bestIsPain = true;
        }
      }
    }
    if (bestAxis >= 0) return (bestAxis, bestIsPain);
    return null;
  }

  void _updateFromPosition(Offset local, double cx, double cy, int axisIndex, {bool setPain = false}) {
    final dx = local.dx - cx;
    final dy = local.dy - cy;
    final a = _spineAxes[axisIndex].angleRad;
    final ax = math.cos(a);
    final ay = math.sin(a);
    var projection = dx * ax + dy * ay;
    projection = projection.clamp(0.0, _radius);
    final t = projection / _radius;
    if (setPain) {
      _setPainSegmentForAxis(axisIndex, t);
    } else {
      _setValueForAxis(axisIndex, t);
    }
  }
}

class _SpineRomPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final List<RomMovementDef> defs;
  final List<RomFinding> findings;

  _SpineRomPainter({
    required this.center,
    required this.radius,
    required this.defs,
    required this.findings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const centerDotRadius = 6.0;

    // Center dot
    canvas.drawCircle(center, centerDotRadius, Paint()..color = Colors.black);

    for (var i = 0; i < _spineAxes.length; i++) {
      final axis = _spineAxes[i];
      final isRotation = i >= 4;
      final endX = center.dx + radius * math.cos(axis.angleRad);
      final endY = center.dy + radius * math.sin(axis.angleRad);

      // Axis line
      canvas.drawLine(
        center,
        Offset(endX, endY),
        Paint()
          ..color = isRotation ? Colors.blue : Colors.black
          ..strokeWidth = isRotation ? 2 : 1.5,
      );

      // Light grey "pain" track alongside (left of) each axis – tap here to mark pain
      const painTrackOffset = 10.0;
      final perpX = -math.sin(axis.angleRad) * painTrackOffset;
      final perpY = math.cos(axis.angleRad) * painTrackOffset;
      canvas.drawLine(
        Offset(center.dx + perpX, center.dy + perpY),
        Offset(endX + perpX, endY + perpY),
        Paint()
          ..color = Colors.grey.shade300
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );

      // Label at end
      final labelOffset = 18.0;
      final labelX = center.dx + (radius + labelOffset) * math.cos(axis.angleRad);
      final labelY = center.dy + (radius + labelOffset) * math.sin(axis.angleRad);
      _drawLabel(canvas, axis.label, Offset(labelX, labelY), axis.angleRad);

      // Red pain segment (left side of axis): draw from painFrom to painTo
      double? painFromVal;
      double? painToVal;
      RomMovementDef? matchedDef;
      RomFinding? matchedFinding;
      _axisMatch(defs, findings, axis, (d, f) {
        matchedDef = d;
        matchedFinding = f;
        painFromVal = f.painFrom ?? f.painAt;
        painToVal = f.painTo ?? f.painAt;
      });
      if (matchedDef != null && matchedFinding != null && matchedFinding!.painful && (painFromVal != null || painToVal != null)) {
        final maxVal = (matchedDef!.maxDeg > 0 ? matchedDef!.maxDeg : 100).toDouble();
        double fromVal = (painFromVal ?? painToVal ?? 0).toDouble();
        double toVal = (painToVal ?? painFromVal ?? 0).toDouble();
        if (fromVal > toVal) { final tmp = fromVal; fromVal = toVal; toVal = tmp; }
        if (fromVal == toVal) {
          final half = 0.025 * maxVal;
          fromVal = (fromVal - half).clamp(0.0, maxVal);
          toVal = (toVal + half).clamp(0.0, maxVal);
        }
        final t0 = (fromVal / maxVal).clamp(0.0, 1.0);
        final t1 = (toVal / maxVal).clamp(0.0, 1.0);
        final p0x = center.dx + (radius * t0) * math.cos(axis.angleRad);
        final p0y = center.dy + (radius * t0) * math.sin(axis.angleRad);
        final p1x = center.dx + (radius * t1) * math.cos(axis.angleRad);
        final p1y = center.dy + (radius * t1) * math.sin(axis.angleRad);
        const leftOffset = 10.0;
        final painPerpX = -math.sin(axis.angleRad) * leftOffset;
        final painPerpY = math.cos(axis.angleRad) * leftOffset;
        canvas.drawLine(
          Offset(p0x + painPerpX, p0y + painPerpY),
          Offset(p1x + painPerpX, p1y + painPerpY),
          Paint()
            ..color = const Color(0xFFC62828)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke,
        );
      }

      // Marker (X) along axis – diagram uses diagramValue only (independent of list degree/%)
      double? diagramVal;
      _axisMatch(defs, findings, axis, (d, f) {
        matchedDef = d;
        diagramVal = f.diagramValue;
      });
      if (matchedDef != null && diagramVal != null) {
        final maxVal = (matchedDef!.maxDeg > 0 ? matchedDef!.maxDeg : 100).toDouble();
        final v = diagramVal!;
        final t = (v >= 0) ? (v / maxVal).clamp(0.0, 1.0) : 0.0;
        final mx = center.dx + (radius * t) * math.cos(axis.angleRad);
        final my = center.dy + (radius * t) * math.sin(axis.angleRad);
        _drawMarker(canvas, Offset(mx, my));
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset at, double angle) {
    final span = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.black87,
        fontWeight: FontWeight.w500,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    // Left-side axes: place text to the left of axis end, no flip (readable L→R)
    final onLeft = math.cos(angle) < 0;
    final dx = onLeft ? -tp.width : 0.0;
    final dy = -tp.height / 2;
    canvas.save();
    canvas.translate(at.dx + dx, at.dy + dy);
    if (!onLeft && (angle < -math.pi / 2 || angle > math.pi / 2)) {
      canvas.rotate(math.pi);
      canvas.translate(-tp.width, 0);
    }
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void _drawMarker(Canvas canvas, Offset at) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const r = 10.0;
    canvas.drawLine(Offset(at.dx - r * 0.7, at.dy - r * 0.7), Offset(at.dx + r * 0.7, at.dy + r * 0.7), paint);
    canvas.drawLine(Offset(at.dx + r * 0.7, at.dy - r * 0.7), Offset(at.dx - r * 0.7, at.dy + r * 0.7), paint);
  }

  @override
  bool shouldRepaint(covariant _SpineRomPainter old) =>
      old.center != center || old.radius != radius ||
      old.findings.length != findings.length ||
      old.defs != defs;
}

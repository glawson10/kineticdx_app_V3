// lib/shared/ui/sticky_tab_button.dart
// Sticky tab on the edge of the shell/workspace.

import 'package:flutter/material.dart';

class StickyTabButton extends StatelessWidget {
  const StickyTabButton({
    super.key,
    required this.icon,
    this.iconSize = 24,
    this.arrowPointsLeft = false,
    this.useDarkerStyle = false,
    required this.onTap,
    this.tooltip,
  });

  static const double restingHeight = 48;

  final IconData icon;
  final double iconSize;
  final bool arrowPointsLeft;
  final bool useDarkerStyle;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = useDarkerStyle
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: restingHeight,
          width: restingHeight,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

/// Angled sticky tab: light purple fill, darker purple border, right edge slanted in.
class AngledStickyTabButton extends StatelessWidget {
  const AngledStickyTabButton({
    super.key,
    required this.icon,
    this.iconSize = 20,
    required this.onTap,
    this.tooltip,
  });

  static const double restingHeight = 48;
  static const double width = 52;
  /// How far the right edge is cut in (bottom-right inset) — angled upwards on the right.
  static const double slant = 12;

  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final String? tooltip;

  static const Color _fillColor = Color(0xFFEDE7F6);   // light purple
  static const Color _borderColor = Color(0xFF6A4C93); // darker purple
  static const Color _iconColor = Color(0xFF4A3D6B);

  /// Shape from drawing: full top, right edge angles upward (bottom-right cut in).
  static Path _path(Size size) {
    const s = slant;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)           // full top
      ..lineTo(size.width - s, size.height)  // right edge angled up (bottom-right inset)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          width: width,
          height: restingHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(width, restingHeight),
                painter: _AngledTabPainter(path: _path(Size(width, restingHeight))),
              ),
              Icon(icon, size: iconSize, color: _iconColor),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

class _AngledTabPainter extends CustomPainter {
  _AngledTabPainter({required this.path});

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(path, Paint()..color = AngledStickyTabButton._fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = AngledStickyTabButton._borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

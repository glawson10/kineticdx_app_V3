// lib/features/shell/shell_overlay_scope.dart
// Scope for overlay content that can close the shell (e.g. calendar tools).
// Inherited so booking screen can read shellRightEdge and closeShell.

import 'package:flutter/material.dart';

class ShellOverlayScope extends InheritedWidget {
  const ShellOverlayScope({
    super.key,
    required this.closeShell,
    required this.shellRightEdge,
    required super.child,
  });

  final VoidCallback closeShell;
  final double shellRightEdge;

  static ShellOverlayScope? _scopeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellOverlayScope>();
  }

  static double getShellRightEdge(BuildContext context) {
    return _scopeOf(context)?.shellRightEdge ?? 0;
  }

  static VoidCallback? maybeCloseShell(BuildContext context) {
    return _scopeOf(context)?.closeShell;
  }

  @override
  bool updateShouldNotify(ShellOverlayScope oldWidget) {
    return closeShell != oldWidget.closeShell ||
        shellRightEdge != oldWidget.shellRightEdge;
  }
}

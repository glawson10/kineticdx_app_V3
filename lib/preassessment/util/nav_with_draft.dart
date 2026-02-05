import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/intake_draft_controller.dart';

/// Push a route while preserving the existing IntakeDraftController provider scope.
Future<T?> pushWithDraft<T>(BuildContext context, Widget child) {
  final draft = context.read<IntakeDraftController>();
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<IntakeDraftController>.value(
        value: draft,
        child: child,
      ),
    ),
  );
}

/// Replace the current route while preserving the existing IntakeDraftController provider scope.
Future<T?> replaceWithDraft<T>(BuildContext context, Widget child) {
  final draft = context.read<IntakeDraftController>();
  return Navigator.of(context).pushReplacement<T, T>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<IntakeDraftController>.value(
        value: draft,
        child: child,
      ),
    ),
  );
}

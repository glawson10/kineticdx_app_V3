import 'package:flutter/material.dart';

class IntakeNav {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static NavigatorState get nav {
    final s = key.currentState;
    if (s == null) {
      throw StateError('Bad state: IntakeNav.key.currentState is null (Navigator not ready)');
    }
    return s;
  }
}

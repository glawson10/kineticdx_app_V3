// lib/preassessment/util/web_actions.dart
//
// Conditional import wrapper so we can use dart:html ONLY on web.
export 'web_actions_stub.dart' if (dart.library.html) 'web_actions_web.dart';

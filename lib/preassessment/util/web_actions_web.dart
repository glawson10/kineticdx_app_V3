// lib/preassessment/util/web_actions_web.dart
//
// Web-only implementation using dart:html.

import 'dart:html' as html;

bool get isWebRuntime => true;

void openUrl(String url) {
  html.window.location.assign(url);
}

void closeWindow() {
  html.window.close();
}

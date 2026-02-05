// lib/preassessment/util/web_actions_stub.dart
//
// Non-web fallback (Android/iOS/desktop). Safe no-ops.

bool get isWebRuntime => false;

void openUrl(String url) {
  // No-op on non-web (Phase 3). You can later use url_launcher if desired.
}

void closeWindow() {
  // No-op on non-web.
}

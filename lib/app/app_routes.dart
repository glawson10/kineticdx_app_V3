// lib/app/app_routes.dart

class AppRoutes {
  // ─────────────────────────────
  // Public (no auth required)
  // ─────────────────────────────

  /// Video intro screen
  static const String publicIntro = '/public';

  /// Public brand home (Book / Prices buttons)
  static const String publicHome = '/public/home';

  /// Public price list
  static const String priceList = '/price-list';

  /// ✅ Canonical public booking route (USED EVERYWHERE)
  static const String patientBookSimple = '/patient-book-simple';

  /// ✅ Legacy aliases (old QR codes, old versions)
  static const String patientBookSimpleLegacy1 = '/patient/book-simple';
  static const String patientBookSimpleLegacy2 = '/patient/book/simple';
  static const String patientBookSimpleLegacy3 = '/patient-book-simple';

  /// Pre-assessment flow (public, after booking)
  static const String preassessmentConsent = '/preassessment/consent';

  /// ✅ Intake root (some bootstraps briefly hit this)
  static const String intakeRoot = '/intake';

  /// ✅ NEW: Intake deep-link start route (from email/SMS)
  /// Example: /intake/start?c=clinicId&t=inviteToken
  static const String intakeStart = '/intake/start';

  /// ✅ General questionnaire token entry (public)
  /// Example: /q/general/<token>
  static const String generalQuestionnaireTokenBase = '/q/general';

  // ─────────────────────────────
  // Clinician (auth required)
  // ─────────────────────────────

  static const String clinicianLogin = '/clinician/login';
  static const String clinicianHome = '/clinician/home';

  /// Clinic-specific login portal: /c/{clinicId}
  /// Use path segments: ['c', clinicId].
  static String clinicPortal(String clinicId) => '/c/${clinicId.trim()}';

  /// Accept invite (auth required). Token in query: ?token=...
  /// Supports composite token: clinicId.rawToken
  static const String acceptInvite = '/invite/accept';
}

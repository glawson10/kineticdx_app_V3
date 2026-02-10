// lib/app/public_app.dart
//
// Minimal public router (if you ever boot a separate PublicApp).
// Also namespaced IntakeStartScreen to avoid type-resolution collisions.

import 'package:flutter/material.dart';

import '../features/public/ui/intro_screen.dart';
import '../features/public/ui/price_list_screen.dart';
import '../features/public/ui/patient_booking_simple_screen.dart';
import '../preassessment/ui/preassessment_consent_entry_screen.dart';
import '../preassessment/screens/intake_start_screen.dart' as intake;
import '../preassessment/screens/general_questionnaire_token_screen.dart';

class PublicApp extends StatelessWidget {
  const PublicApp({super.key});

  String _norm(String path) {
    var p = path.trim();
    if (p.isEmpty) return '/';
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  String _clinicIdFrom(Uri uri) =>
      (uri.queryParameters['c'] ??
              uri.queryParameters['clinicId'] ??
              uri.queryParameters['clinic'] ??
              '')
          .trim();

  String _corpFrom(Uri uri) =>
      (uri.queryParameters['corp'] ??
              uri.queryParameters['corporate'] ??
              uri.queryParameters['corpCode'] ??
              uri.queryParameters['code'] ??
              '')
          .trim();

  bool _isBookingAlias(String p) {
    return p == '/patient-book-simple' ||
        p == '/patient/book-simple' ||
        p == '/patient/book/simple' ||
        p == '/patient-book-simple';
  }

  String? _generalTokenFromPath(Uri uri) {
    // Support either:
    // - /q/general/<token>
    // - /q/general/<token>/   (trailing slash)
    // - //q/general/<token>   (double slash in generated links)
    // - /q/general?token=<token> or /q/general?t=<token> (fallback)
    final qpToken = (uri.queryParameters['t'] ?? uri.queryParameters['token'] ?? '')
        .trim();
    if (qpToken.isNotEmpty) return qpToken;

    final segments =
        uri.pathSegments.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) return null;

    // Keep it strict: match the LAST 3 non-empty segments exactly.
    final n = segments.length;
    if (segments[n - 3] == 'q' && segments[n - 2] == 'general') {
      final token = segments[n - 1].trim();
      return token.isEmpty ? null : token;
    }

    return null;
  }

  MaterialPageRoute _missingClinic(String routeName) {
    return MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Missing clinicId.\n\nUse ?c=<CLINIC_ID> in the URL.\n'
              'Example:\n/public?c=WXyILCpdFfdtNhjzeXqD',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/public',
      onGenerateRoute: (settings) {
        final uri = Uri.parse((settings.name ?? '/public').trim());
        final path = _norm(uri.path);

        final clinicId = _clinicIdFrom(uri);
        final corp = _corpFrom(uri);
        final corpOrNull = corp.isEmpty ? null : corp;
        final generalToken = _generalTokenFromPath(uri);

        if (generalToken != null) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => GeneralQuestionnaireTokenScreen(
              token: generalToken,
            ),
          );
        }

        switch (path) {
          case '/':
          case '/public': {
            if (clinicId.isEmpty) return _missingClinic(path);

            return MaterialPageRoute(
              settings: settings,
              builder: (_) => IntroScreen(
                clinicId: clinicId,
                corporateCode: corpOrNull,
              ),
            );
          }

          case '/home': {
            // Optional convenience route for public home
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const PublicHomeScreen(),
            );
          }

          case '/price-list': {
            if (clinicId.isEmpty) return _missingClinic(path);

            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PriceListScreen(
                clinicId: clinicId,
                corporateCode: corpOrNull,
              ),
            );
          }

          case '/preassessment/consent': {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => PreassessmentConsentEntryScreen(
                fallbackClinicId: clinicId.isEmpty ? null : clinicId,
              ),
            );
          }

          case '/intake/start': {
            // IntakeStartScreen reads query params itself (?c & ?t)
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const intake.IntakeStartScreen(),
            );
          }

          default: {
            if (_isBookingAlias(path)) {
              if (clinicId.isEmpty) return _missingClinic(path);

              return MaterialPageRoute(
                settings: settings,
                builder: (_) => PatientBookingSimpleScreen(
                  clinicId: clinicId,
                  clinicianId: null,
                  initialCorporateCodeFromUrl: corpOrNull,
                ),
              );
            }

            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const Scaffold(
                body: Center(child: Text('Not found')),
              ),
            );
          }
        }
      },
    );
  }
}

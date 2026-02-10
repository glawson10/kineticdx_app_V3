// lib/app/app.dart
//
// MyApp router with hash-route normalization + public boot mode.
//
// IMPORTANT:
// - Do NOT put WidgetBuilder closures inside a `const` Map/List anywhere.
//   Closures are never const in Dart.
// - If you have something like `static const routes = { '/x': (_) => ... }`
//   in app_routes.dart or elsewhere, change it to `static final` (or remove const).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_gate.dart';
import 'clinic_context.dart';
import 'clinic_session_scope.dart';
import 'app_routes.dart';

import '../data/repositories/appointments_repository.dart';
import '../data/repositories/memberships_repository.dart';
import '../data/repositories/services_repository.dart';
import '../data/repositories/clinic_repository.dart';

// Staff repos
import '../data/repositories/staff_repository.dart';
import '../data/repositories/staff_profile_repository.dart';

// Public UI
import '../features/public/ui/intro_screen.dart';
import '../features/public/ui/price_list_screen.dart';
import '../features/public/ui/patient_booking_simple_screen.dart';

// Preassessment
import '../preassessment/ui/preassessment_consent_entry_screen.dart';
import '../preassessment/screens/intake_start_screen.dart' as intake;
import '../preassessment/screens/general_questionnaire_token_screen.dart';

// Auth
import '../features/auth/accept_invite_screen.dart';
import '../features/auth/clinic_entry_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _asTrimmedString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> _args(RouteSettings settings) {
    final a = settings.arguments;
    if (a is Map<String, dynamic>) return a;
    if (a is Map) return Map<String, dynamic>.from(a);
    return const <String, dynamic>{};
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final s = (v ?? '').trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String _normalizePath(String path) {
    var p = path.trim();
    if (p.isEmpty) return '/';
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  bool _isBookingAliasPath(String normalizedPath) {
    return normalizedPath == AppRoutes.patientBookSimple ||
        normalizedPath == AppRoutes.patientBookSimpleLegacy1 ||
        normalizedPath == AppRoutes.patientBookSimpleLegacy2 ||
        normalizedPath == AppRoutes.patientBookSimpleLegacy3;
  }

  String? _generalTokenFromUri(Uri uri) {
    // Support either:
    // - /q/general/<token>
    // - /q/general/<token>/   (trailing slash)
    // - //q/general/<token>   (double slash in generated links)
    // - /q/general?token=<token> or /q/general?t=<token> (fallback)
    final qpToken = _asTrimmedString(
      uri.queryParameters['t'] ?? uri.queryParameters['token'],
    );
    if (qpToken != null) return qpToken;

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

  /// Enable verbose route logs in hosted builds by adding:
  ///   &routeLogs=1
  /// Works with hash-routing too: #/path?...&routeLogs=1
  bool _routeLogsEnabled() {
    try {
      // normal qp (before #)
      final qp = Uri.base.queryParameters;
      final v1 = (qp['routeLogs'] ?? '').trim().toLowerCase();
      if (v1 == '1' || v1 == 'true' || v1 == 'yes') return true;

      // fragment qp (after #)
      final frag = Uri.base.fragment.trim();
      if (frag.isEmpty) return false;

      final fragUri = Uri.parse(frag.startsWith('/') ? frag : '/$frag');
      final v2 =
          (fragUri.queryParameters['routeLogs'] ?? '').trim().toLowerCase();
      return v2 == '1' || v2 == 'true' || v2 == 'yes';
    } catch (_) {
      return false;
    }
  }

  void _log(String msg) {
    // ignore: avoid_print
    print(msg);
  }

  /// Normalize settings.name so "/#/intake/start?c=..&t=.." becomes "/intake/start?c=..&t=.."
  Uri _routeUri(RouteSettings settings) {
    final raw = (settings.name ?? '/').trim();
    if (raw.isEmpty) return Uri.parse('/');

    // full URL case
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final u = Uri.parse(raw);
      if (u.fragment.trim().isNotEmpty) {
        final frag = u.fragment.trim();
        final fragRoute = frag.startsWith('/') ? frag : '/$frag';
        return Uri.parse(fragRoute);
      }
      return u;
    }

    // contains '#'
    final hashIndex = raw.indexOf('#');
    if (hashIndex != -1) {
      final frag = raw.substring(hashIndex + 1).trim();
      if (frag.isEmpty) return Uri.parse('/');
      final fragRoute = frag.startsWith('/') ? frag : '/$frag';
      return Uri.parse(fragRoute);
    }

    return Uri.parse(raw);
  }

  String? _resolveClinicIdFromBrowserQuery() {
    try {
      final qp = Uri.base.queryParameters;
      return _asTrimmedString(qp['clinicId'] ?? qp['clinic'] ?? qp['c']);
    } catch (_) {
      return null;
    }
  }

  String? _resolveCorpFromBrowserQuery() {
    try {
      final qp = Uri.base.queryParameters;
      return _asTrimmedString(_firstNonEmpty([
        qp['corp'],
        qp['corporate'],
        qp['corpCode'],
        qp['code'],
      ]));
    } catch (_) {
      return null;
    }
  }

  String? _clinicIdFor(RouteSettings settings, Uri routeUri) {
    final a = _args(settings);
    return _asTrimmedString(a['clinicId']) ??
        _asTrimmedString(
          _firstNonEmpty([
            routeUri.queryParameters['clinicId'],
            routeUri.queryParameters['clinic'],
            routeUri.queryParameters['c'],
          ]),
        ) ??
        _resolveClinicIdFromBrowserQuery();
  }

  String? _corpFor(RouteSettings settings, Uri routeUri) {
    final a = _args(settings);
    return _asTrimmedString(a['corporateCode']) ??
        _asTrimmedString(a['corp']) ??
        _asTrimmedString(
          _firstNonEmpty([
            routeUri.queryParameters['corp'],
            routeUri.queryParameters['corporate'],
            routeUri.queryParameters['corpCode'],
            routeUri.queryParameters['code'],
          ]),
        ) ??
        _resolveCorpFromBrowserQuery();
  }

  static const Map<String, String> _corpToClinicId = <String, String>{
    'ResistantAI': 'WXyILCpdFfdtNhjzeXqD',
  };

  String? _resolveClinicIdForLegacyBooking(Uri routeUri, String? corp) {
    final fromQuery = _asTrimmedString(
      _firstNonEmpty([
        routeUri.queryParameters['c'],
        routeUri.queryParameters['clinicId'],
        routeUri.queryParameters['clinic'],
      ]),
    );
    if (fromQuery != null) return fromQuery;

    final code = (corp ?? '').trim();
    if (code.isEmpty) return null;
    return _corpToClinicId[code];
  }

  MaterialPageRoute _missingClinicRoute(String routeName) {
    return MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Missing clinicId.\n\nOpen the public portal with ?c=<ID>\n'
              'Example:\n/public?c=WXyILCpdFfdtNhjzeXqD\n\n'
              'or navigate with arguments: { clinicId: <ID> }\n\n'
              'If you are using an old corporate QR code, ensure its corp code is mapped to a clinicId.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  MaterialPageRoute _intakeMissingRoute(String routeName) {
    return MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'This pre-assessment link is incomplete.\n\n'
              'Please use the full link from the email.\n\n'
              'Expected:\n/intake/start?c=<clinicId>&t=<token>',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  /// Determine initial route for web (supports hash routes).
  String _resolveInitialRouteFull() {
    // Hash route case (#/path?query)
    final frag = Uri.base.fragment.trim();
    if (frag.isNotEmpty) {
      return frag.startsWith('/') ? frag : '/$frag';
    }

    final path = Uri.base.path.trim().isEmpty ? '/' : Uri.base.path.trim();
    final query = Uri.base.hasQuery ? '?${Uri.base.query}' : '';

    final qp = Uri.base.queryParameters;
    final hasClinic =
        (qp['c'] ?? qp['clinicId'] ?? qp['clinic'] ?? '').trim().isNotEmpty;

    // If landing on "/" with clinic in query, treat as public intro
    if (path == '/' && hasClinic) {
      return '${AppRoutes.publicIntro}$query';
    }

    return '$path$query';
  }

  bool _isPublicBoot(Uri uri) {
    final path = _normalizePath(uri.path);

    if (path == AppRoutes.publicIntro ||
        path == AppRoutes.publicHome ||
        path == AppRoutes.priceList ||
        _isBookingAliasPath(path) ||
        path == AppRoutes.preassessmentConsent ||
        path == AppRoutes.intakeStart ||
        _generalTokenFromUri(uri) != null ||
        path == AcceptInviteScreen.routeName ||
        path == '/intake') {
      return true;
    }

    if (path == '/') {
      final qp = uri.queryParameters;
      final hasClinic =
          (qp['c'] ?? qp['clinicId'] ?? qp['clinic'] ?? '').trim().isNotEmpty;
      return hasClinic;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Router
  // ---------------------------------------------------------------------------

  /// Returns clinicId if path is /c/{clinicId}, else null.
  String? _clinicIdFromPortalPath(String normalizedPath) {
    if (!normalizedPath.startsWith('/c/')) return null;
    final segments = normalizedPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[0] == 'c') {
      final id = segments[1].trim();
      return id.isEmpty ? null : id;
    }
    return null;
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final routeUri = _routeUri(settings);
    final normalizedPath = _normalizePath(routeUri.path);

    final shouldLog = _routeLogsEnabled();
    if (shouldLog) {
      _log('🧭 onGenerateRoute');
      _log('   raw settings.name: ${settings.name}');
      _log('   parsed uri: $routeUri');
      _log('   path: ${routeUri.path} -> normalized: $normalizedPath');
      _log('   query: ${routeUri.queryParameters}');
      _log('   base.uri: ${Uri.base}');
      _log('   base.fragment: ${Uri.base.fragment}');
      _log('   kReleaseMode=$kReleaseMode kDebugMode=$kDebugMode');
    }

    // Clinic-specific login portal: /c/{clinicId}
    final portalClinicId = _clinicIdFromPortalPath(normalizedPath);
    if (portalClinicId != null) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AuthGate(clinicId: portalClinicId),
      );
    }

    switch (normalizedPath) {
      case '/': {
        final clinicId = _resolveClinicIdFromBrowserQuery();
        final corp = _resolveCorpFromBrowserQuery();

        if (clinicId != null && clinicId.isNotEmpty) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => IntroScreen(
              clinicId: clinicId,
              corporateCode: corp,
            ),
          );
        }

        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ClinicEntryScreen(),
        );
      }

      case AcceptInviteScreen.routeName: {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AcceptInviteScreen(),
        );
      }

      case AppRoutes.publicIntro: {
        final clinicId = _clinicIdFor(settings, routeUri);
        final corp = _corpFor(settings, routeUri);

        return MaterialPageRoute(
          settings: settings,
          builder: (_) => IntroScreen(
            clinicId: clinicId,
            corporateCode: corp,
          ),
        );
      }

      case AppRoutes.publicHome: {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const PublicHomeScreen(),
        );
      }

      case AppRoutes.priceList: {
        final clinicId = _clinicIdFor(settings, routeUri);
        final corp = _corpFor(settings, routeUri);

        return MaterialPageRoute(
          settings: settings,
          builder: (_) => PriceListScreen(
            clinicId: clinicId,
            corporateCode: corp,
          ),
        );
      }

      case AppRoutes.preassessmentConsent: {
        final clinicId = _clinicIdFor(settings, routeUri);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => PreassessmentConsentEntryScreen(
            fallbackClinicId: clinicId,
          ),
        );
      }

      case AppRoutes.intakeStart: {
        // IntakeStartScreen reads query params itself (?c & ?t)
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const intake.IntakeStartScreen(),
        );
      }

      case '/intake': {
        return _intakeMissingRoute(normalizedPath);
      }

      case AppRoutes.clinicianLogin:
      case AppRoutes.clinicianHome: {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AuthGate(),
        );
      }

      default: {
        final generalToken = _generalTokenFromUri(routeUri);
        if (generalToken != null) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => GeneralQuestionnaireTokenScreen(
              token: generalToken,
            ),
          );
        }

        // Booking screen (canonical + legacy aliases)
        if (_isBookingAliasPath(normalizedPath)) {
          final corp = _corpFor(settings, routeUri);

          var clinicId = _clinicIdFor(settings, routeUri);
          clinicId ??= _resolveClinicIdForLegacyBooking(routeUri, corp);

          if (clinicId == null || clinicId.trim().isEmpty) {
            return _missingClinicRoute(normalizedPath);
          }

          final a = _args(settings);
          final clinicianId = _asTrimmedString(a['clinicianId']);

          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PatientBookingSimpleScreen(
              clinicId: clinicId!.trim(),
              clinicianId: clinicianId,
              initialCorporateCodeFromUrl: corp,
            ),
          );
        }

        if (shouldLog) {
          _log('❌ Unknown route (normalized): $normalizedPath');
          _log('   full settings.name: ${settings.name}');
        }

        return MaterialPageRoute(
          settings: settings,
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Unknown route: ${settings.name ?? "(null)"}'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialRouteFull = _resolveInitialRouteFull();
    final initialUri = Uri.parse(initialRouteFull);
    final isPublicBoot = _isPublicBoot(initialUri);

    if (isPublicBoot) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'KineticDx',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'OpenSans',
        ),
        initialRoute: initialRouteFull,
        onGenerateRoute: _onGenerateRoute,
      );
    }

    return MultiProvider(
      providers: [
        Provider<MembershipsRepository>(create: (_) => MembershipsRepository()),
        Provider<AppointmentsRepository>(create: (_) => AppointmentsRepository()),
        Provider<ServicesRepository>(create: (_) => ServicesRepository()),
        Provider<ClinicRepository>(create: (_) => ClinicRepository()),
        Provider<StaffRepository>(create: (_) => StaffRepository()),
        Provider<StaffProfileRepository>(create: (_) => StaffProfileRepository()),
        ChangeNotifierProvider<ClinicContext>(create: (_) => ClinicContext()),
      ],
      child: ClinicSessionScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KineticDx',
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'OpenSans',
          ),
          initialRoute: initialRouteFull,
          onGenerateRoute: _onGenerateRoute,
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

import 'app/app.dart';
import 'services/deep_link_service.dart';

const String _firebaseEnv =
    String.fromEnvironment('FIREBASE_ENV', defaultValue: 'prod');

bool get _isDev => _firebaseEnv.toLowerCase() == 'dev';
bool get _isProd => _firebaseEnv.toLowerCase() == 'prod';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!_isDev && !_isProd) {
    throw StateError(
      "Invalid FIREBASE_ENV='$_firebaseEnv'. Use FIREBASE_ENV=dev or FIREBASE_ENV=prod",
    );
  }

  final FirebaseOptions options = _isDev
      ? dev.DefaultFirebaseOptions.currentPlatform
      : prod.DefaultFirebaseOptions.currentPlatform;

  await Firebase.initializeApp(options: options);

  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  // Complete email link sign-in if app was opened via magic link
  final deepLink = DeepLinkService();
  final linkResult = await deepLink.handleInitialLink();
  if (linkResult is InitialLinkError && kDebugMode) {
    debugPrint('Deep link sign-in: ${linkResult.message}');
  }
  if (linkResult is InitialLinkMissingEmail && kDebugMode) {
    debugPrint('Email link opened but no stored email; user can request link again.');
  }

  debugPrint('================================================');
  debugPrint('🔥 FIREBASE_ENV=$_firebaseEnv');
  debugPrint('🔥 Firebase projectId: ${Firebase.app().options.projectId}');
  debugPrint('🔥 Firebase appId: ${Firebase.app().options.appId}');
  debugPrint('================================================');

  runApp(const MyApp());
}

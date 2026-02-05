import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

import 'app/app.dart';

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

  debugPrint('================================================');
  debugPrint('🔥 FIREBASE_ENV=$_firebaseEnv');
  debugPrint('🔥 Firebase projectId: ${Firebase.app().options.projectId}');
  debugPrint('🔥 Firebase appId: ${Firebase.app().options.appId}');
  debugPrint('================================================');

  runApp(const MyApp());
}

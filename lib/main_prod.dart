import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options_prod.dart' as prod;
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: prod.DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

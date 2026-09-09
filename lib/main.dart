import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/app/trackademic_app.dart';
import 'package:trackademic/firebase_options.dart';
import 'package:trackademic/core/firebase/firebase_emulator_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseEmulatorConfig.connect();

  runApp(const TrackademicApp());
}

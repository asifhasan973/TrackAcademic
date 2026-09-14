import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/app/trackademic_app.dart';
import 'package:trackademic/firebase_options.dart';
import 'package:trackademic/core/firebase/app_check_config.dart';
import 'package:trackademic/core/firebase/firebase_emulator_config.dart';
import 'package:trackademic/core/services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseEmulatorConfig.connect();
  await AppCheckConfig.initialize();
  await PushNotificationService().initialize();

  runApp(const TrackademicApp());
}

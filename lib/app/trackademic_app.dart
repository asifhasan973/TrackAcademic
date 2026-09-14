import 'package:flutter/material.dart';
import 'package:trackademic/core/services/push_notification_service.dart';
import 'package:trackademic/core/theme/app_theme.dart';
import 'package:trackademic/features/authentication/presentation/auth_gate.dart';

class TrackademicApp extends StatelessWidget {
  const TrackademicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'TrackAcademic',
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}

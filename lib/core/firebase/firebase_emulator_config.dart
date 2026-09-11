import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseEmulatorConfig {
  static const bool enabled = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  static const String customHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );

  static bool _connected = false;

  static Future<void> connect() async {
    if (!enabled || _connected) {
      return;
    }

    final defaultHost =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';

    final host = customHost.trim().isNotEmpty ? customHost.trim() : defaultHost;

    await FirebaseAuth.instance.useAuthEmulator(host, 9099);

    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

    FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).useFunctionsEmulator(host, 5001);

    await FirebaseStorage.instance.useStorageEmulator(host, 9199);

    _connected = true;
  }
}

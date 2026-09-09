import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:trackademic/core/firebase/firebase_emulator_config.dart';

/// Configuration for Firebase App Check.
///
/// Designed to protect backend resources from abuse while keeping local
/// emulator development, debug runs, and testing unblocked.
abstract final class AppCheckConfig {
  static bool _initialized = false;

  /// Initializes App Check according to the runtime environment.
  ///
  /// - When [FirebaseEmulatorConfig.enabled] is true, App Check is bypassed
  ///   so local emulator workflows never encounter attestation errors.
  /// - In debug mode, official debug providers are used for Android and Apple.
  /// - In production mode, Play Integrity and App Attest are configured.
  static Future<void> initialize({String? webRecaptchaSiteKey}) async {
    if (_initialized) {
      return;
    }

    // Bypass App Check completely when running against local Firebase emulators.
    if (FirebaseEmulatorConfig.enabled) {
      _initialized = true;
      return;
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb:
            webRecaptchaSiteKey != null && webRecaptchaSiteKey.isNotEmpty
            ? ReCaptchaV3Provider(webRecaptchaSiteKey)
            : null,
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
      _initialized = true;
    } catch (e) {
      // In development environments without Google Play services,
      // log and allow development to continue gracefully.
      debugPrint('App Check initialization notice: $e');
    }
  }
}

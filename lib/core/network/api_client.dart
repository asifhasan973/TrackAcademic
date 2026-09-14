import 'dart:convert';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../firebase/firebase_emulator_config.dart';

class ApiException implements Exception {
  final String code;
  final String message;

  const ApiException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

abstract final class ApiClient {
  static const String _configuredBackendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );

  static const Set<String> _safeIdempotentOperations = {
    'submitAttendance',
    'createAttendanceSession',
    'setAttendanceStatus',
    'closeAttendanceSession',
    'createCourse',
    'requestJoinCourse',
    'respondCourseJoinRequest',
    'registerUser',
    'saveAssessmentMarks',
    'publishAssessment',
  };

  static String get backendUrl {
    if (FirebaseEmulatorConfig.enabled) {
      return '';
    }

    final url = _configuredBackendUrl.trim();
    if (url.isEmpty) {
      throw const ApiException(
        code: 'failed-precondition',
        message:
            'Online mode requires BACKEND_URL to be configured with a valid HTTPS endpoint.',
      );
    }

    if (!url.startsWith('https://')) {
      throw const ApiException(
        code: 'failed-precondition',
        message: 'BACKEND_URL must use HTTPS protocol in production.',
      );
    }

    if (url.contains('localhost') ||
        url.contains('127.0.0.1') ||
        url.contains('10.0.2.2') ||
        url.contains('placeholder')) {
      throw const ApiException(
        code: 'failed-precondition',
        message: 'BACKEND_URL cannot point to localhost or placeholder in online mode.',
      );
    }

    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> data, {
    bool isIdempotent = false,
  }) async {
    final isQuery = isIdempotent || operation == 'getCourseJoinCode';
    final requestData = Map<String, dynamic>.from(data);
    final String? idempotencyKey;
    if (!isQuery) {
      idempotencyKey = (requestData['idempotencyKey'] as String?) ??
          'ta_${DateTime.now().millisecondsSinceEpoch}_${operation}_${Random().nextInt(999999)}';
      requestData['idempotencyKey'] = idempotencyKey;
    } else {
      idempotencyKey = null;
    }

    if (FirebaseEmulatorConfig.enabled) {
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-south1',
        ).httpsCallable(operation);
        final result = await callable.call<Map<String, dynamic>>(requestData);
        return result.data;
      } on FirebaseFunctionsException catch (error) {
        throw ApiException(
          code: error.code,
          message: error.message ?? 'The operation failed.',
        );
      } catch (error) {
        if (error is ApiException) rethrow;
        throw ApiException(
          code: 'internal',
          message: error.toString(),
        );
      }
    }

    final endpoint = '$backendUrl/$operation';
    final uri = Uri.parse(endpoint);

    final user = FirebaseAuth.instance.currentUser;
    String? idToken;
    if (user != null) {
      idToken = await user.getIdToken();
    }

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };

    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }
    if (idempotencyKey != null) {
      headers['X-Idempotency-Key'] = idempotencyKey;
    }

    final isProtectedMutation =
        idempotencyKey != null && _safeIdempotentOperations.contains(operation);
    final canSafelyRetry = isQuery || isProtectedMutation;
    final maxAttempts = canSafelyRetry ? 2 : 1;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      http.Response response;
      try {
        response = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(requestData),
            )
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // Only retry transient network timeout or connection reset if safe and attempt 1
        if (canSafelyRetry && attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        throw const ApiException(
          code: 'unavailable',
          message:
              'Network connection timed out. Please check your internet connection and try again.',
        );
      }

      Map<String, dynamic>? bodyJson;
      try {
        if (response.body.isNotEmpty) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            bodyJson = decoded;
          }
        }
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (bodyJson != null) {
          if (bodyJson.containsKey('result') &&
              bodyJson['result'] is Map<String, dynamic>) {
            return bodyJson['result'] as Map<String, dynamic>;
          }
          if (bodyJson.containsKey('data') &&
              bodyJson['data'] is Map<String, dynamic>) {
            return bodyJson['data'] as Map<String, dynamic>;
          }
          return bodyJson;
        }
        return <String, dynamic>{};
      }

      String errorMessage = 'Server returned error status ${response.statusCode}.';
      String errorCode = 'internal';

      if (bodyJson != null && bodyJson.containsKey('error')) {
        final err = bodyJson['error'];
        if (err is Map<String, dynamic>) {
          errorMessage = err['message']?.toString() ?? errorMessage;
          errorCode = err['code']?.toString() ?? errorCode;
        } else if (err is String) {
          errorMessage = err;
        }
      }

      // If token expired or session unauthenticated, attempt one bounded recovery with fresh token
      if ((response.statusCode == 401 || errorCode == 'unauthenticated') &&
          attempt < maxAttempts &&
          user != null) {
        try {
          final freshToken = await user.getIdToken(true);
          headers['Authorization'] = 'Bearer $freshToken';
          continue;
        } catch (_) {}
      }

      // For 502/503/504 transient server errors, retry once with backoff if safe
      if ((response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504) &&
          canSafelyRetry &&
          attempt < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 800));
        continue;
      }

      throw ApiException(
        code: errorCode,
        message: errorMessage,
      );
    }

    throw const ApiException(
      code: 'unavailable',
      message: 'Server unreachable. Please try again.',
    );
  }
}

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/features/student/courses/presentation/student_course_detail_screen.dart';
import 'package:trackademic/features/teacher/courses/presentation/teacher_courses_screen.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[PushNotificationService] Background message received: ${message.messageId}',
  );
}

class PushNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentToken;
  String? _boundUserId;

  /// Hashes token into a safe Firestore document ID
  String _tokenDocId(String token) {
    final clean = base64Url
        .encode(utf8.encode(token))
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return clean.length > 40 ? clean.substring(0, 40) : clean;
  }

  /// Initializes FCM listeners, background handler, and foreground handlers
  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) async {
        _currentToken = newToken;
        if (_boundUserId != null) {
          await _saveTokenToFirestore(_boundUserId!, newToken);
        }
      });

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '[PushNotificationService] Foreground message: ${message.notification?.title}',
        );
        _showForegroundNotificationBanner(message);
      });

      // Background notification tap listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[PushNotificationService] Opened from background notification');
        handleNotificationPayload(message.data);
      });

      // Check if launched from terminated state via notification
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[PushNotificationService] App launched from terminated state');
        Future.delayed(const Duration(milliseconds: 800), () {
          handleNotificationPayload(initialMessage.data);
        });
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Initialization error: $e');
    }
  }

  /// Requests notification permission on Android 13+ / iOS
  Future<bool> requestPermission() async {
    if (kIsWeb) return true;
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[PushNotificationService] Permission request error: $e');
      return false;
    }
  }

  /// Registers and saves the device token to users/{userId}/deviceTokens/{tokenId}
  Future<void> registerUserDevice(String userId) async {
    if (kIsWeb || userId.isEmpty) return;

    try {
      _boundUserId = userId;
      final token = await _fcm.getToken();
      if (token == null) return;
      _currentToken = token;

      await _saveTokenToFirestore(userId, token);
    } catch (e) {
      debugPrint('[PushNotificationService] Failed to register token for $userId: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    final docId = _tokenDocId(token);
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('deviceTokens')
        .doc(docId);

    final snapshot = await docRef.get();
    final now = FieldValue.serverTimestamp();

    if (!snapshot.exists) {
      await docRef.set({
        'token': token,
        'platform': 'android',
        'createdAt': now,
        'updatedAt': now,
      });
    } else {
      await docRef.update({
        'token': token,
        'platform': 'android',
        'updatedAt': now,
      });
    }
    debugPrint('[PushNotificationService] Saved token doc $docId for user $userId');
  }

  /// Unbinds and deletes token on logout or account switch
  Future<void> unregisterUserDevice() async {
    final userId = _boundUserId ?? FirebaseAuth.instance.currentUser?.uid;
    final token = _currentToken;

    if (userId != null && token != null) {
      try {
        final docId = _tokenDocId(token);
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('deviceTokens')
            .doc(docId)
            .delete();
        debugPrint('[PushNotificationService] Unregistered token for $userId');
      } catch (e) {
        debugPrint('[PushNotificationService] Unregister error: $e');
      }
    }

    _boundUserId = null;
    _currentToken = null;
  }

  void _showForegroundNotificationBanner(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final title = message.notification?.title ?? 'TrackAcademic';
    final body = message.notification?.body ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty)
              Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => handleNotificationPayload(message.data),
        ),
      ),
    );
  }

  void handleNotificationPayload(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint('[PushNotificationService] Sign-in gated: user not signed in.');
      return;
    }

    final type = data['type'] as String? ?? '';
    final courseId = data['courseId'] as String? ?? '';
    final entityId = data['entityId'] as String? ?? '';

    debugPrint(
      '[PushNotificationService] Handling notification payload type: $type, courseId: $courseId, entityId: $entityId',
    );

    try {
      switch (type) {
        case 'attendance_session_created':
        case 'attendance_session_started':
          if (courseId.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentCourseDetailScreen(
                  courseId: courseId,
                  initialTabIndex: 0,
                  highlightSessionId: entityId.isNotEmpty ? entityId : null,
                ),
              ),
            );
          }
          break;

        case 'join_request':
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TeacherCoursesScreen(
                initialManageCourseId: courseId.isNotEmpty ? courseId : null,
                initialRequestId: entityId.isNotEmpty ? entityId : null,
                initialTabIndex: 0,
              ),
            ),
          );
          break;

        case 'join_request_approved':
        case 'join_request_rejected':
          if (courseId.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentCourseDetailScreen(
                  courseId: courseId,
                ),
              ),
            );
          }
          break;

        case 'marks_published':
        case 'assessment_publish':
        case 'assessment_published':
          if (courseId.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentCourseDetailScreen(
                  courseId: courseId,
                  initialTabIndex: 1,
                  highlightAssessmentId: entityId.isNotEmpty ? entityId : null,
                ),
              ),
            );
          }
          break;

        default:
          debugPrint('[PushNotificationService] Unhandled notification type: $type');
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Navigation routing error: $e');
    }
  }
}

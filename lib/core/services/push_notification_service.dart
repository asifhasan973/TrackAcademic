import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/features/student/courses/presentation/student_course_detail_screen.dart';
import 'package:trackademic/features/student/schedule/presentation/student_schedule_screen.dart';
import 'package:trackademic/features/teacher/courses/presentation/teacher_courses_screen.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';

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

  static const MethodChannel _platformChannel =
      MethodChannel('com.trackademic/notification_channel');

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentToken;
  String? _boundUserId;

  Map<String, dynamic>? _pendingPayload;
  bool _isAppReady = false;
  final Set<int> _displayedNotificationIds = <int>{};

  /// Hashes token into a safe Firestore document ID
  String _tokenDocId(String token) {
    final clean = base64Url
        .encode(utf8.encode(token))
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return clean.length > 40 ? clean.substring(0, 40) : clean;
  }

  /// Initializes FCM listeners, background handler, and native platform notification channels
  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listen for notification taps originating from native Kotlin Activity
      _platformChannel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationTapped') {
          final payload = Map<String, dynamic>.from(call.arguments as Map);
          debugPrint('[PushNotificationService] Native onNotificationTapped: $payload');
          if (_isAppReady) {
            handleNotificationPayload(payload);
          } else {
            _pendingPayload = payload;
          }
        }
      });

      // Check if launched with a pending native notification intent
      try {
        final initialNativePayload = await _platformChannel
            .invokeMethod<Map<dynamic, dynamic>>('getPendingNotificationPayload');
        if (initialNativePayload != null && initialNativePayload.isNotEmpty) {
          _pendingPayload = Map<String, dynamic>.from(initialNativePayload);
          debugPrint('[PushNotificationService] Retrieved native pending payload: $_pendingPayload');
        }
      } catch (_) {}

      // Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) async {
        _currentToken = newToken;
        if (_boundUserId != null) {
          await _saveTokenToFirestore(_boundUserId!, newToken);
        }
      });

      // Foreground message listener: show real system notification + SnackBar
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '[PushNotificationService] Foreground message: ${message.notification?.title}',
        );
        _handleForegroundMessage(message);
      });

      // Background notification tap listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[PushNotificationService] Opened from background notification');
        if (_isAppReady) {
          handleNotificationPayload(message.data);
        } else {
          _pendingPayload = message.data;
        }
      });

      // Check if launched from terminated state via FCM
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[PushNotificationService] App launched from terminated state via FCM');
        _pendingPayload = initialMessage.data;
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Initialization error: $e');
    }
  }

  /// Notifies the push service that navigation, auth, and profile are ready to handle pending targets.
  void onAppReady(BuildContext context, AppUserProfile profile) {
    _isAppReady = true;
    if (_pendingPayload != null) {
      final payload = _pendingPayload!;
      _pendingPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleNotificationPayload(payload, targetContext: context);
      });
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
    _isAppReady = false;
    _pendingPayload = null;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'TrackAcademic';
    final body = message.notification?.body ?? '';
    final notifId = (message.data['notificationId'] ?? message.messageId ?? title).hashCode;

    // Show real Android system notification without duplicate stacking
    if (!_displayedNotificationIds.contains(notifId)) {
      _displayedNotificationIds.add(notifId);
      if (_displayedNotificationIds.length > 100) {
        _displayedNotificationIds.remove(_displayedNotificationIds.first);
      }

      if (!kIsWeb) {
        try {
          _platformChannel.invokeMethod('showNotification', {
            'id': notifId,
            'title': title,
            'body': body,
            'payload': message.data,
          });
        } catch (e) {
          debugPrint('[PushNotificationService] Failed to post system notification: $e');
        }
      }
    }

    // Also display in-app banner for immediate tapping
    _showForegroundNotificationBanner(message);
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

  /// Routes notification action payloads to the appropriate screen after checking authorization
  void handleNotificationPayload(Map<String, dynamic> data, {BuildContext? targetContext}) async {
    final context = targetContext ?? navigatorKey.currentContext;
    if (context == null) {
      _pendingPayload = data;
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint('[PushNotificationService] Sign-in gated: user not signed in. Retaining pending payload.');
      _pendingPayload = data;
      return;
    }

    // Check intended recipient to avoid cross-user routing
    final targetUserId = data['userId'] as String?;
    if (targetUserId != null && targetUserId.isNotEmpty && targetUserId != currentUser.uid) {
      debugPrint('[PushNotificationService] Recipient mismatch: target=$targetUserId, current=${currentUser.uid}');
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
        case 'class_reminder':
          // Device-local class reminder tapped: carry course/schedule & recipient info, verify access, and open appropriate timetable screen
          if (courseId.isNotEmpty) {
            final exists = await _verifyCourseAccessible(courseId);
            if (!context.mounted) return;
            if (!exists) {
              _showTargetUnavailableNotice(context, 'This class schedule is no longer accessible.');
              return;
            }
          }
          try {
            final profile = await const AuthService().loadCurrentProfile();
            if (!context.mounted) return;
            if ((profile.role ?? '').toLowerCase() == 'teacher') {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Class Timetable')),
                    body: TeacherScheduleScreen(
                      initialCourseId: courseId.isNotEmpty ? courseId : null,
                    ),
                  ),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Class Timetable')),
                    body: const StudentScheduleScreen(),
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint('[PushNotificationService] Failed to load profile for class_reminder routing: $e');
          }
          break;

        case 'attendance_session_created':
        case 'attendance_session_started':
          if (courseId.isNotEmpty) {
            final exists = await _verifyCourseAccessible(courseId);
            if (!context.mounted) return;
            if (!exists) {
              _showTargetUnavailableNotice(context, 'This attendance session is no longer active.');
              return;
            }
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
          if (courseId.isNotEmpty) {
            final exists = await _verifyCourseAccessible(courseId);
            if (!context.mounted) return;
            if (!exists) {
              _showTargetUnavailableNotice(context, 'Course is not currently accessible.');
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StudentCourseDetailScreen(
                  courseId: courseId,
                ),
              ),
            );
          }
          break;

        case 'join_request_rejected':
          // Rejection must NOT navigate to StudentCourseDetailScreen as student has no course permissions
          _showJoinRequestRejectedNotice(context, data);
          break;

        case 'marks_published':
        case 'assessment_publish':
        case 'assessment_published':
          if (courseId.isNotEmpty) {
            final exists = await _verifyCourseAccessible(courseId);
            if (!context.mounted) return;
            if (!exists) {
              _showTargetUnavailableNotice(context, 'This assessment is no longer accessible.');
              return;
            }
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

  Future<bool> _verifyCourseAccessible(String courseId) async {
    try {
      final doc = await _firestore.collection('courses').doc(courseId).get();
      return doc.exists && doc.data()?['isActive'] == true;
    } catch (_) {
      return false;
    }
  }

  void _showJoinRequestRejectedNotice(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Join Request Status'),
          ],
        ),
        content: const Text(
          'Your request to join this course was not approved by the instructor. Please contact your instructor if you believe this is an error.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTargetUnavailableNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.grey.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

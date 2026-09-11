import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/core/models/in_app_notification.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/services/notification_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/student/attendance/presentation/student_attendance_screen.dart';
import 'package:trackademic/features/student/dashboard/presentation/student_dashboard_screen.dart';
import 'package:trackademic/features/student/marks/presentation/student_marks_screen.dart';
import 'package:trackademic/features/student/schedule/presentation/student_schedule_screen.dart';
import 'package:trackademic/features/teacher/attendance/presentation/teacher_create_attendance_screen.dart';
import 'package:trackademic/features/teacher/courses/presentation/teacher_courses_screen.dart';
import 'package:trackademic/features/teacher/marks/presentation/teacher_marks_screen.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _authService = AuthService();
  static const _notificationService = NotificationService();

  bool _isMarkingAll = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;
    final userId = currentUser?.uid ?? '';

    if (userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(
          child: Text(
            'Please sign in to view your notifications.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<int>(
            stream: _notificationService.streamUnreadCount(userId),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return const SizedBox.shrink();

              return TextButton.icon(
                onPressed: _isMarkingAll ? null : () => _markAllAsRead(userId),
                icon: _isMarkingAll
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Mark all as read'),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<InAppNotification>>(
        stream: _notificationService.streamNotifications(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 48,
                    ),
                    const SizedBox(height: AppSpacing.regular),
                    Text(
                      'Failed to load notifications: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          final notifications = snapshot.data ?? const [];

          if (notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.extraLarge),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.informationBackground,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    const Text(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text(
                      'You are all caught up! Updates about course activity, '
                      'attendance, marks, and schedules will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.large,
                  vertical: AppSpacing.regular,
                ),
                itemCount: notifications.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.small),
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return _NotificationTile(
                    notification: notification,
                    onTap: () => _handleNotificationTap(userId, notification),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleNotificationTap(
    String userId,
    InAppNotification notification,
  ) async {
    // 1. Mark as read first with safe error handling
    if (!notification.isRead) {
      try {
        await _notificationService.markAsRead(userId, notification.id);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update notification read status: $error',
              ),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }

    if (!mounted) return;

    // 2. Fetch authenticated user profile to verify role and active status
    final database = FirebaseFirestore.instance;
    final Map<String, dynamic>? userData;
    try {
      final userDoc = await database.collection('users').doc(userId).get();
      if (!userDoc.exists || userDoc.data()?['isActive'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your user account is inactive or not found.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }
      userData = userDoc.data();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to verify user permissions: $error'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final role = userData?['role'] as String? ?? '';
    final isTeacher = role == 'teacher';
    final isStudent = role == 'student';

    if (!isTeacher && !isStudent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unrecognized user role for notification navigation.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final courseId = notification.courseId.trim();
    bool isArchived = false;

    // 3. If notification references a course, verify course existence and ownership/enrollment
    if (courseId.isNotEmpty) {
      try {
        final courseDoc = await database
            .collection('courses')
            .doc(courseId)
            .get();
        if (!courseDoc.exists || courseDoc.data() == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This course no longer exists.'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
          return;
        }

        final courseData = courseDoc.data()!;
        isArchived = courseData['isActive'] != true;

        if (isTeacher) {
          final teacherId = courseData['teacherId'] as String? ?? '';
          if (teacherId != userId) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You do not manage this course.'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
            return;
          }
        } else if (isStudent) {
          final enrollmentDoc = await database
              .collection('courses')
              .doc(courseId)
              .collection('students')
              .doc(userId)
              .get();

          if (!enrollmentDoc.exists ||
              enrollmentDoc.data()?['isActive'] == false) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'You are not currently enrolled in this course.',
                  ),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
            return;
          }
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to verify course access: $error'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    // 4. Resolve destination screen based on role, notification type, and archive status
    final (navResult, notice) = NotificationNavigationResolver.resolve(
      role: role,
      notificationType: notification.type,
      isArchived: isArchived,
    );

    if (notice != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(notice),
            backgroundColor: AppColors.information,
          ),
        );
      }
      return;
    }

    Widget? targetScreen;
    switch (navResult) {
      case NotificationNavigationResult.teacherCourses:
        targetScreen = const TeacherCoursesScreen();
        break;
      case NotificationNavigationResult.teacherAttendance:
        targetScreen = const TeacherCreateAttendanceScreen(
          showBackButton: true,
        );
        break;
      case NotificationNavigationResult.teacherMarks:
        targetScreen = const TeacherMarksScreen();
        break;
      case NotificationNavigationResult.teacherSchedule:
        targetScreen = const TeacherScheduleScreen();
        break;
      case NotificationNavigationResult.studentDashboard:
        targetScreen = _buildStudentDashboard();
        break;
      case NotificationNavigationResult.studentAttendance:
        targetScreen = const StudentAttendanceScreen();
        break;
      case NotificationNavigationResult.studentMarks:
        targetScreen = const StudentMarksScreen();
        break;
      case NotificationNavigationResult.studentSchedule:
        targetScreen = const StudentScheduleScreen();
        break;
      case NotificationNavigationResult.archivedNotice:
      case NotificationNavigationResult.unrecognizedRole:
        break;
    }

    if (targetScreen != null && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => targetScreen!));
    }
  }

  Widget _buildStudentDashboard() {
    return StudentDashboardScreen(
      onOpenAttendance: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const StudentAttendanceScreen(),
          ),
        );
      },
      onOpenMarks: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const StudentMarksScreen()),
        );
      },
      onOpenSchedule: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const StudentScheduleScreen(),
          ),
        );
      },
    );
  }

  Future<void> _markAllAsRead(String userId) async {
    setState(() {
      _isMarkingAll = true;
    });

    try {
      final result = await _notificationService.markAllAsRead(userId);
      if (mounted && result.count > 0) {
        final message = result.hasMore
            ? 'Marked ${result.count} notifications as read (more unread items remaining).'
            : 'Marked ${result.count} notifications as read.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update notifications: $error'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingAll = false;
        });
      }
    }
  }
}

class _NotificationTile extends StatelessWidget {
  final InAppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    final (icon, iconColor, bgIconColor) = _getVisuals(notification.type);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.medium),
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.informationBackground.withValues(alpha: 0.35)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(
            color: isUnread
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
            width: isUnread ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bgIconColor,
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: isUnread
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: AppSpacing.small),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.extraSmall),
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: isUnread
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  if (notification.createdAt != null) ...[
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      notification.timeAgo(),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, Color) _getVisuals(String type) {
    switch (type) {
      case 'attendance_session_created':
      case 'attendance_session_started':
        return (
          Icons.how_to_reg_rounded,
          AppColors.success,
          AppColors.successBackground,
        );
      case 'assessment_published':
        return (
          Icons.analytics_rounded,
          AppColors.primary,
          AppColors.informationBackground,
        );
      case 'course_archived':
        return (
          Icons.archive_outlined,
          AppColors.warning,
          AppColors.warningBackground,
        );
      case 'course_reactivated':
        return (
          Icons.unarchive_outlined,
          AppColors.success,
          AppColors.successBackground,
        );
      case 'join_request':
        return (
          Icons.person_add_rounded,
          AppColors.primary,
          AppColors.informationBackground,
        );
      case 'join_request_approved':
        return (
          Icons.check_circle_outline_rounded,
          AppColors.success,
          AppColors.successBackground,
        );
      case 'join_request_rejected':
        return (
          Icons.cancel_outlined,
          AppColors.danger,
          AppColors.dangerBackground,
        );
      case 'schedule_created':
      case 'schedule_updated':
      case 'schedule_deleted':
        return (
          Icons.calendar_month_rounded,
          AppColors.primary,
          AppColors.informationBackground,
        );
      default:
        return (
          Icons.notifications_rounded,
          AppColors.primary,
          AppColors.informationBackground,
        );
    }
  }
}

enum NotificationNavigationResult {
  teacherCourses,
  teacherAttendance,
  teacherMarks,
  teacherSchedule,
  studentDashboard,
  studentAttendance,
  studentMarks,
  studentSchedule,
  archivedNotice,
  unrecognizedRole,
}

class NotificationNavigationResolver {
  static (NotificationNavigationResult, String?) resolve({
    required String role,
    required String notificationType,
    required bool isArchived,
  }) {
    if (role != 'teacher' && role != 'student') {
      return (NotificationNavigationResult.unrecognizedRole, null);
    }

    if (role == 'teacher') {
      switch (notificationType) {
        case 'join_request':
        case 'course_archived':
        case 'course_reactivated':
          return (NotificationNavigationResult.teacherCourses, null);
        case 'attendance_session_created':
          if (isArchived) {
            return (
              NotificationNavigationResult.archivedNotice,
              'This course is archived. Cannot manage live attendance.',
            );
          }
          return (NotificationNavigationResult.teacherAttendance, null);
        case 'assessment_publish':
        case 'assessment_published':
          return (NotificationNavigationResult.teacherMarks, null);
        case 'schedule_created':
        case 'schedule_updated':
        case 'schedule_deleted':
          return (NotificationNavigationResult.teacherSchedule, null);
        default:
          return (NotificationNavigationResult.teacherCourses, null);
      }
    } else {
      switch (notificationType) {
        case 'join_request_approved':
        case 'join_request_rejected':
        case 'course_archived':
        case 'course_reactivated':
          return (NotificationNavigationResult.studentDashboard, null);
        case 'attendance_session_created':
          if (isArchived) {
            return (
              NotificationNavigationResult.archivedNotice,
              'This course is archived. Historical attendance is viewable in your records.',
            );
          }
          return (NotificationNavigationResult.studentAttendance, null);
        case 'assessment_publish':
        case 'assessment_published':
          return (NotificationNavigationResult.studentMarks, null);
        case 'schedule_created':
        case 'schedule_updated':
        case 'schedule_deleted':
          return (NotificationNavigationResult.studentSchedule, null);
        default:
          return (NotificationNavigationResult.studentDashboard, null);
      }
    }
  }
}

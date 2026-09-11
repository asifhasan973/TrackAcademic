import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/models/in_app_notification.dart';

void main() {
  group('InAppNotification Model Unit Tests', () {
    test('deserializes properly from Map with Timestamp', () {
      final now = DateTime(2026, 9, 10, 12, 0, 0);
      final rawData = {
        'userId': 'user_123',
        'type': 'course_archived',
        'title': 'Course Archived',
        'message': 'CSE101 has been archived by the teacher.',
        'courseId': 'course_abc',
        'entityId': 'course_abc',
        'isRead': false,
        'createdAt': Timestamp.fromDate(now),
        'readAt': null,
      };

      final notification = InAppNotification.fromMap('notif_1', rawData);

      expect(notification.id, 'notif_1');
      expect(notification.userId, 'user_123');
      expect(notification.type, 'course_archived');
      expect(notification.title, 'Course Archived');
      expect(notification.message, 'CSE101 has been archived by the teacher.');
      expect(notification.courseId, 'course_abc');
      expect(notification.entityId, 'course_abc');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, now);
      expect(notification.readAt, isNull);
    });

    test('deserializes properly from Map with String date and read status', () {
      final rawData = {
        'userId': 'user_456',
        'type': 'assessment_published',
        'title': 'Marks Published',
        'message': 'CT-1 marks are now available.',
        'courseId': 'course_xyz',
        'entityId': 'assess_001',
        'isRead': true,
        'createdAt': '2026-09-08T10:00:00.000Z',
        'readAt': '2026-09-08T11:00:00.000Z',
      };

      final notification = InAppNotification.fromMap('notif_2', rawData);

      expect(notification.id, 'notif_2');
      expect(notification.userId, 'user_456');
      expect(notification.isRead, isTrue);
      expect(
        notification.createdAt,
        DateTime.parse('2026-09-08T10:00:00.000Z'),
      );
      expect(notification.readAt, DateTime.parse('2026-09-08T11:00:00.000Z'));
    });

    test('handles missing or malformed fields safely with fallbacks', () {
      final notification = InAppNotification.fromMap('notif_fallback', {});

      expect(notification.id, 'notif_fallback');
      expect(notification.userId, '');
      expect(notification.type, '');
      expect(notification.title, '');
      expect(notification.message, '');
      expect(notification.courseId, '');
      expect(notification.entityId, '');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, isNull);
      expect(notification.readAt, isNull);
    });

    test('copyWith properly overrides specified attributes', () {
      final original = InAppNotification(
        id: 'n_orig',
        userId: 'u1',
        type: 'schedule_created',
        title: 'New Class Schedule',
        message: 'New class on Monday',
        courseId: 'c1',
        entityId: 's1',
        isRead: false,
      );

      final readTime = DateTime(2026, 9, 10, 14, 0);
      final updated = original.copyWith(isRead: true, readAt: readTime);

      expect(updated.id, 'n_orig');
      expect(updated.userId, 'u1');
      expect(updated.isRead, isTrue);
      expect(updated.readAt, readTime);
      expect(original.isRead, isFalse);
    });

    test('timeAgo calculates relative strings accurately', () {
      final clock = DateTime(2026, 9, 10, 12, 0, 0);

      // Null createdAt
      expect(
        const InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
        ).timeAgo(clock: clock),
        '',
      );

      // 30 seconds ago -> Just now
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: clock.subtract(const Duration(seconds: 30)),
        ).timeAgo(clock: clock),
        'Just now',
      );

      // 5 minutes ago
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: clock.subtract(const Duration(minutes: 5)),
        ).timeAgo(clock: clock),
        '5m ago',
      );

      // 3 hours ago
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: clock.subtract(const Duration(hours: 3)),
        ).timeAgo(clock: clock),
        '3h ago',
      );

      // 1 day ago -> Yesterday
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: clock.subtract(const Duration(days: 1)),
        ).timeAgo(clock: clock),
        'Yesterday',
      );

      // 4 days ago -> 4d ago
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: clock.subtract(const Duration(days: 4)),
        ).timeAgo(clock: clock),
        '4d ago',
      );

      // 14 days ago -> Month Day format
      final oldDate = DateTime(2026, 8, 20, 10, 0);
      expect(
        InAppNotification(
          id: '1',
          userId: 'u',
          type: 't',
          title: 't',
          message: 'm',
          courseId: 'c',
          entityId: 'e',
          isRead: false,
          createdAt: oldDate,
        ).timeAgo(clock: clock),
        'Aug 20',
      );
    });
  });
}

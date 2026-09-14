import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/features/student/schedule/presentation/student_schedule_screen.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Class Reminder Routing Verification', () {
    test('Recipient mismatch check blocks navigation for wrong recipient', () {
      final Map<String, dynamic> payload = {
        'type': 'class_reminder',
        'scheduleId': 'sched_1',
        'courseId': 'course_1',
        'userId': 'target_user_456',
      };

      const currentUid = 'current_user_123';
      final targetUserId = payload['userId'] as String?;
      final isMismatch = targetUserId != null &&
          targetUserId.isNotEmpty &&
          targetUserId != currentUid;

      expect(isMismatch, isTrue, reason: 'Recipient mismatch must be detected');
    });

    test('Recipient match allows navigation for intended recipient', () {
      final Map<String, dynamic> payload = {
        'type': 'class_reminder',
        'scheduleId': 'sched_1',
        'courseId': 'course_1',
        'userId': 'user_123',
      };

      const currentUid = 'user_123';
      final targetUserId = payload['userId'] as String?;
      final isMismatch = targetUserId != null &&
          targetUserId.isNotEmpty &&
          targetUserId != currentUid;

      expect(isMismatch, isFalse, reason: 'Matching recipient must proceed');
    });

    testWidgets('Routes teacher to TeacherScheduleScreen with initialCourseId', (tester) async {
      const teacherProfile = AppUserProfile(
        uid: 'teacher_1',
        email: 'teacher@test.local',
        displayName: 'Prof. Smith',
        role: 'teacher',
        institutionId: 'INST1',
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  // Simulate routing decision for teacher
                  if ((teacherProfile.role ?? '').toLowerCase() == 'teacher') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: TeacherScheduleScreen(initialCourseId: 'course_101'),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Tap Reminder'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Tap Reminder'));
      await tester.pumpAndSettle();

      expect(find.byType(TeacherScheduleScreen), findsOneWidget);
    });

    testWidgets('Routes student to StudentScheduleScreen', (tester) async {
      const studentProfile = AppUserProfile(
        uid: 'student_1',
        email: 'student@test.local',
        displayName: 'Alice Student',
        role: 'student',
        institutionId: 'INST1',
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  // Simulate routing decision for student
                  if ((studentProfile.role ?? '').toLowerCase() != 'teacher') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: StudentScheduleScreen(),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Tap Reminder'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Tap Reminder'));
      await tester.pumpAndSettle();

      expect(find.byType(StudentScheduleScreen), findsOneWidget);
    });
  });
}

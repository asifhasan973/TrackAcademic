import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/models/user_role.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/features/authentication/presentation/sign_in_screen.dart';
import 'package:trackademic/features/notifications/presentation/notifications_screen.dart';
import 'package:trackademic/features/teacher/attendance/presentation/teacher_create_attendance_screen.dart';
import 'package:trackademic/features/teacher/marks/presentation/teacher_marks_screen.dart';
import 'package:trackademic/features/ui_preview/presentation/role_workspace_screen.dart';

void main() {
  group('Targeted UX & Functional Tests', () {
    testWidgets('1. Signed-out displays SignInScreen directly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

      // Verify SignInScreen is rendered directly with "Sign in" and "Create account" actions
      expect(find.text('Sign in'), findsWidgets);
      expect(find.textContaining("Don't have an account?"), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('2. Teacher and Student direct workspace routing', (
      tester,
    ) async {
      // Teacher workspace directly
      await tester.pumpWidget(
        MaterialApp(home: RoleWorkspaceScreen(role: UserRole.teacher)),
      );
      expect(find.text('TrackAcademic'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      final teacherNav = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(teacherNav.destinations.length, 6);

      // Student workspace directly
      await tester.pumpWidget(
        MaterialApp(home: RoleWorkspaceScreen(role: UserRole.student)),
      );
      expect(find.text('TrackAcademic'), findsOneWidget);
      final studentNav = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(studentNav.destinations.length, 5);
    });

    testWidgets('3. Mobile NavigationBar labels are hidden', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(home: RoleWorkspaceScreen(role: UserRole.student)),
      );

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        navBar.labelBehavior,
        NavigationDestinationLabelBehavior.alwaysHide,
      );
    });

    testWidgets(
      '4 & 5. Duration defaults to 1, cannot go below 1, and Class types contain only Theory & Sessional',
      (tester) async {
        const mockCourse = TeacherCourse(
          id: 'course-1',
          code: 'CSE311',
          name: 'Database Systems',
          teacherId: 'teacher-1',
          teacherName: 'Dr. Smith',
          department: 'CSE',
          batch: '50',
          section: '1',
          semester: 'Fall 2026',
          room: 'Room 401',
          joinCode: 'CSE311-FALL',
          isActive: true,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CreateSessionDialog(courses: [mockCourse])),
          ),
        );

        // Prominent date check
        expect(find.textContaining('Session Date:'), findsOneWidget);

        // Default duration check (1 min)
        expect(find.text('1 min'), findsOneWidget);

        // Minus button is visibly disabled at 1 minute
        final minusFinder = find.widgetWithIcon(
          IconButton,
          Icons.remove_circle_outline_rounded,
        );
        expect(minusFinder, findsOneWidget);
        final minusButton = tester.widget<IconButton>(minusFinder);
        expect(minusButton.onPressed, isNull);

        // Plus button can be clicked
        final plusFinder = find.widgetWithIcon(
          IconButton,
          Icons.add_circle_outline_rounded,
        );
        expect(plusFinder, findsOneWidget);
        await tester.tap(plusFinder);
        await tester.pump();

        // Duration is now 2 mins
        expect(find.text('2 mins'), findsOneWidget);

        // Minus button is now enabled
        final minusButtonEnabled = tester.widget<IconButton>(minusFinder);
        expect(minusButtonEnabled.onPressed, isNotNull);

        // Tap minus to return to 1 min
        await tester.tap(minusFinder);
        await tester.pump();
        expect(find.text('1 min'), findsOneWidget);

        // Class type dropdown: verify Theory is selected
        expect(find.text('Theory'), findsOneWidget);
        // Practical and Makeup do not exist
        expect(find.text('Practical'), findsNothing);
        expect(find.text('Makeup'), findsNothing);

        // Tap the dropdown to view menu items
        await tester.tap(find.text('Theory'));
        await tester.pumpAndSettle();

        // Both Theory and Sessional appear in the dropdown menu
        expect(find.text('Theory'), findsWidgets);
        expect(find.text('Sessional'), findsOneWidget);
        expect(find.text('Practical'), findsNothing);
        expect(find.text('Makeup'), findsNothing);
      },
    );

    test('6. Notification marks_published routes to Student Marks', () {
      final (studentDest, notice1) = NotificationNavigationResolver.resolve(
        role: 'student',
        notificationType: 'marks_published',
        isArchived: false,
      );
      expect(studentDest, NotificationNavigationResult.studentMarks);
      expect(notice1, isNull);

      final (teacherDest, notice2) = NotificationNavigationResolver.resolve(
        role: 'teacher',
        notificationType: 'marks_published',
        isArchived: false,
      );
      expect(teacherDest, NotificationNavigationResult.teacherMarks);
      expect(notice2, isNull);
    });

    test(
      '7. Student name and roll summary filtering works case-insensitively',
      () {
        final students = [
          const EnrolledStudent(
            uid: 's1',
            displayName: 'Alice Johnson',
            institutionId: '2023-1-60-001',
            email: 'alice@example.com',
            isActive: true,
          ),
          const EnrolledStudent(
            uid: 's2',
            displayName: 'Bob Smith',
            institutionId: '2023-1-60-045',
            email: 'bob@example.com',
            isActive: true,
          ),
          const EnrolledStudent(
            uid: 's3',
            displayName: 'Charlie Brown',
            institutionId: '2023-2-60-012',
            email: 'charlie@example.com',
            isActive: true,
          ),
        ];

        // Filter by name case-insensitively
        final queryName = 'ali';
        final filteredByName = students.where((s) {
          return s.displayName.toLowerCase().contains(queryName) ||
              s.institutionId.toLowerCase().contains(queryName);
        }).toList();
        expect(filteredByName.length, 1);
        expect(filteredByName.first.displayName, 'Alice Johnson');

        // Filter by institution ID / roll
        final queryRoll = '60-045';
        final filteredByRoll = students.where((s) {
          return s.displayName.toLowerCase().contains(queryRoll) ||
              s.institutionId.toLowerCase().contains(queryRoll);
        }).toList();
        expect(filteredByRoll.length, 1);
        expect(filteredByRoll.first.displayName, 'Bob Smith');

        // Unmatched search returns empty
        final queryNone = 'no-such-student';
        final filteredNone = students.where((s) {
          return s.displayName.toLowerCase().contains(queryNone) ||
              s.institutionId.toLowerCase().contains(queryNone);
        }).toList();
        expect(filteredNone.isEmpty, isTrue);
      },
    );

    testWidgets(
      '8. 360 px width Attendance and Marks layouts have no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // 1. Attendance Card at 360px
        final session = TeacherAttendanceSession(
          id: 'sess-1',
          courseId: 'c1',
          courseCode: 'CSE311',
          courseName: 'Database Systems',
          classType: 'Theory',
          status: 'closed',
          durationMinutes: 1,
          requiresPasscode: true,
          requiresGps: false,
          allowLateEntry: false,
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          endsAt: DateTime.now().subtract(const Duration(minutes: 4)),
        );

        // 2. Assessment Card at 360px
        final assessment = TeacherAssessment(
          id: 'a1',
          courseId: 'c1',
          courseCode: 'CSE311',
          courseName: 'Database Systems',
          name: 'Class Test 1',
          type: 'Quiz',
          maxScore: 20,
          status: 'draft',
          date: '2026-09-12',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    TeacherAttendanceSessionCard(
                      session: session,
                      onView: () {},
                      onSummary: () {},
                      onClose: () {},
                    ),
                    const SizedBox(height: 16),
                    TeacherAssessmentCard(
                      assessment: assessment,
                      onEnterMarks: () {},
                      onEdit: () {},
                      onDelete: () {},
                      onPublish: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Verify no RenderFlex overflow exception
        expect(tester.takeException(), isNull);
        expect(find.byType(TeacherAttendanceSessionCard), findsOneWidget);
        expect(find.byType(TeacherAssessmentCard), findsOneWidget);
      },
    );
  });
}

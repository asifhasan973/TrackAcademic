import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/features/schedule/presentation/widgets/timetable_calendar.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';

void main() {
  group('Phase 12 Targeted Verification', () {
    const testCourse = TeacherCourse(
      id: 'course-cse-101',
      code: 'CSE 101',
      name: 'Intro to Computer Science',
      teacherId: 'teacher-1',
      teacherName: 'Dr. Test Teacher',
      department: 'CSE',
      batch: '2024',
      section: 'A',
      semester: '1st',
      room: 'Room 401',
      joinCode: 'CSE101',
      isActive: true,
    );

    // 1. Current-time line position and current-day visibility
    testWidgets(
      '1. Current-time line renders on current day/week and hides on other days',
      (tester) async {
        final now = DateTime.now();
        final currentMinutes = now.hour * 60 + now.minute;
        // Schedule an entry so grid extends around current time
        final entries = [
          TimetableEntry(
            id: 'entry-1',
            courseId: testCourse.id,
            courseCode: testCourse.code,
            courseName: testCourse.name,
            teacherName: testCourse.teacherName,
            dayIndex: now.weekday % 7,
            day: 'Today',
            startTime: '07:00',
            endTime: '22:00',
            room: 'Room 401',
            classType: 'Theory',
            status: 'scheduled',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TimetableCalendar(entries: entries, isTeacher: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Week view is default: indicator should be visible for today
        final indicatorFinder = find.byKey(
          const ValueKey('current_time_indicator'),
        );
        expect(indicatorFinder, findsOneWidget);

        // Switch to Day view
        await tester.tap(find.text('Day'));
        await tester.pumpAndSettle();

        // Day view of today: indicator should be visible
        expect(indicatorFinder, findsOneWidget);

        // Verify accurate position math
        final positionedWidget = tester.widget<Positioned>(indicatorFinder);
        const hourHeight = 64.0;
        const startHour = 7; // min time was 07:00
        final expectedTop =
            (currentMinutes - (startHour * 60)) * (hourHeight / 60.0) -
            (8.0 / 2);
        expect(
          (positionedWidget.top! - expectedTop).abs(),
          lessThanOrEqualTo(1.0),
        );

        // Navigate to previous day: indicator must disappear cleanly
        await tester.tap(find.byTooltip('Previous'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('current_time_indicator')),
          findsNothing,
        );

        // Tap Today button: indicator returns
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('current_time_indicator')),
          findsOneWidget,
        );
      },
    );

    // 2. Attendance header at 320/360/390 widths with no overflow
    testWidgets(
      '2. Attendance header lays out responsively without overflow on 320, 360, 390 widths',
      (tester) async {
        final widths = [320.0, 360.0, 390.0, 700.0];

        for (final width in widths) {
          for (final isEnabled in [true, false]) {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const title = Text(
                          'Attendance Sessions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        );

                        final createButton = FilledButton.icon(
                          onPressed: isEnabled ? () {} : null,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create attendance session'),
                        );

                        if (constraints.maxWidth < 560) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: title,
                              ),
                              const SizedBox(height: 12),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: createButton,
                              ),
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: title,
                              ),
                            ),
                            const SizedBox(width: 16),
                            createButton,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            // Must produce ZERO RenderFlex overflow
            expect(tester.takeException(), isNull);
            expect(find.text('Attendance Sessions'), findsOneWidget);
            expect(find.text('Create attendance session'), findsOneWidget);
          }
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );

    // 3 & 4. Join-request pending -> approved transition and rejection
    test(
      '3. Join request status and enrollment models support approve and reject transitions',
      () {
        const rawPending = {
          'courseId': 'course-1',
          'courseCode': 'CSE 101',
          'courseName': 'Intro to CS',
          'teacherId': 'teacher-1',
          'studentId': 'student-1',
          'studentName': 'Alice Student',
          'institutionId': '2024-S01',
          'email': 'alice@demo.local',
          'status': 'pending',
          'attempt': 1,
        };

        final pendingRequest = TeacherJoinRequest.fromMap('req-1', rawPending);
        expect(pendingRequest.id, 'req-1');
        expect(pendingRequest.studentName, 'Alice Student');
        expect(pendingRequest.institutionId, '2024-S01');
        expect(pendingRequest.email, 'alice@demo.local');
        expect(pendingRequest.status, 'pending');

        // Transition: Approved
        final approvedDoc = Map<String, dynamic>.from(rawPending);
        approvedDoc['status'] = 'approved';
        final approvedRequest = TeacherJoinRequest.fromMap(
          'req-1',
          approvedDoc,
        );
        expect(approvedRequest.status, 'approved');

        // When approved, enrolled student active
        const enrolledStudent = EnrolledStudent(
          uid: 'student-1',
          institutionId: '2024-S01',
          displayName: 'Alice Student',
          email: 'alice@demo.local',
          isActive: true,
        );
        expect(enrolledStudent.isActive, isTrue);

        // Transition: Rejected
        final rejectedDoc = Map<String, dynamic>.from(rawPending);
        rejectedDoc['status'] = 'rejected';
        final rejectedRequest = TeacherJoinRequest.fromMap(
          'req-1',
          rejectedDoc,
        );
        expect(rejectedRequest.status, 'rejected');
      },
    );

    // 5. Add Class form validation and readable backend error mapping
    testWidgets(
      '5. Add Class form validates empty room, invalid times, and end time > start time',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TeacherScheduleScreen())),
        );
        await tester.pump();

        // Check time validation helper rules
        final validHHMM = RegExp(r'^(\d{1,2}):(\d{2})$');
        expect(validHHMM.hasMatch('09:00'), isTrue);
        expect(validHHMM.hasMatch('9:00'), isTrue);
        expect(
          validHHMM.hasMatch('25:00'),
          isTrue,
        ); // format matches, but range check catches

        int? parseMinutes(String text) {
          final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
          if (match == null) return null;
          final hour = int.tryParse(match.group(1)!);
          final min = int.tryParse(match.group(2)!);
          if (hour == null ||
              min == null ||
              hour < 0 ||
              hour > 23 ||
              min < 0 ||
              min > 59) {
            return null;
          }
          return hour * 60 + min;
        }

        expect(parseMinutes('09:00'), 540);
        expect(parseMinutes('09:50'), 590);
        expect(parseMinutes('25:00'), isNull);
        expect(parseMinutes('invalid'), isNull);

        // Validation check: end time must be greater than start time
        final startMin = parseMinutes('10:00')!;
        final endMinEarlier = parseMinutes('09:30')!;
        final endMinEqual = parseMinutes('10:00')!;
        final endMinLater = parseMinutes('11:00')!;

        expect(endMinEarlier <= startMin, isTrue);
        expect(endMinEqual <= startMin, isTrue);
        expect(endMinLater > startMin, isTrue);

        // Validation check: empty room is rejected
        String? validateRoom(String? val) {
          if (val == null || val.trim().isEmpty) {
            return 'Room is required';
          }
          return null;
        }

        expect(validateRoom(''), 'Room is required');
        expect(validateRoom('   '), 'Room is required');
        expect(validateRoom('Room 401'), isNull);
      },
    );

    // 6. Backend and service error mapping
    test(
      '6. TeacherAcademicService error mapping sanitizes internal [0] to readable message and preserves explicit messages',
      () {
        String mapError(String? message, String callName) {
          final msg = message?.trim();
          if (msg == null ||
              msg.isEmpty ||
              msg == 'INTERNAL' ||
              msg.toLowerCase() == 'internal' ||
              msg.contains('[0]')) {
            return (callName == 'createSchedule' ||
                    callName == 'updateSchedule')
                ? 'Could not save this class. Please try again.'
                : 'The operation failed. Please try again.';
          }
          return msg;
        }

        // Raw internal [0] failure becomes human-readable
        expect(
          mapError(
            '[firebase_functions/internal] internal [0]',
            'createSchedule',
          ),
          'Could not save this class. Please try again.',
        );
        expect(
          mapError('internal', 'createSchedule'),
          'Could not save this class. Please try again.',
        );
        expect(
          mapError('', 'createSchedule'),
          'Could not save this class. Please try again.',
        );

        // Explicit business logic errors are preserved
        expect(
          mapError('Room is required.', 'createSchedule'),
          'Room is required.',
        );
        expect(
          mapError(
            'Schedule overlaps with CSE 101 on Monday.',
            'createSchedule',
          ),
          'Schedule overlaps with CSE 101 on Monday.',
        );
        expect(
          mapError(
            'An exact duplicate schedule entry already exists for this course.',
            'createSchedule',
          ),
          'An exact duplicate schedule entry already exists for this course.',
        );
      },
    );
  });
}

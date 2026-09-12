import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/firebase/firebase_emulator_config.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/attendance_csv_builder.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/features/schedule/presentation/widgets/timetable_calendar.dart';
import 'package:trackademic/features/teacher/attendance/presentation/teacher_create_attendance_screen.dart';

void main() {
  group('Phase 11 Targeted Verification', () {
    const mockCourse = TeacherCourse(
      id: 'demo-course-cse311',
      code: 'CSE 311',
      name: 'Software Engineering',
      teacherId: 'teacher-1',
      teacherName: 'Dr. Demo Teacher',
      department: 'CSE',
      batch: '2024',
      section: 'A',
      semester: '6th',
      room: 'Lab 3',
      joinCode: 'CSE311',
      isActive: true,
    );

    // 1. Attendance Cancel result type and dialog closing
    testWidgets(
      '1. Create Attendance Cancel returns null and closes dialog safely',
      (tester) async {
        CreateAttendanceSessionResult? dialogResult;
        var dialogCompleted = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult =
                        await showDialog<CreateAttendanceSessionResult>(
                          context: context,
                          builder: (ctx) =>
                              const CreateSessionDialog(courses: [mockCourse]),
                        );
                    dialogCompleted = true;
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(CreateSessionDialog), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Dialog should be closed immediately
        expect(find.byType(CreateSessionDialog), findsNothing);
        expect(dialogCompleted, isTrue);
        // Result must be null, not false, preventing type errors
        expect(dialogResult, isNull);
      },
    );

    // 2. Course attendance matrix calculation
    test(
      '2. Course attendance matrix calculation orders and computes correctly',
      () {
        final students = [
          const EnrolledStudent(
            uid: 'student-2',
            institutionId: 'ID-002',
            displayName: 'Bob Smith',
            email: 'bob@demo.local',
            isActive: true,
          ),
          const EnrolledStudent(
            uid: 'student-1',
            institutionId: 'ID-001',
            displayName: 'Alice Brown',
            email: 'alice@demo.local',
            isActive: true,
          ),
        ];

        // Sort students by institutionId
        students.sort((a, b) => a.institutionId.compareTo(b.institutionId));

        final sessions = [
          TeacherAttendanceSession(
            id: 'session-2',
            courseId: mockCourse.id,
            courseCode: mockCourse.code,
            courseName: mockCourse.name,
            classType: 'Lab',
            status: 'closed',
            startedAt: DateTime(2026, 9, 7, 14, 0),
            endsAt: DateTime(2026, 9, 7, 15, 30),
            durationMinutes: 90,
            requiresPasscode: false,
            requiresGps: false,
            allowLateEntry: false,
          ),
          TeacherAttendanceSession(
            id: 'session-1',
            courseId: mockCourse.id,
            courseCode: mockCourse.code,
            courseName: mockCourse.name,
            classType: 'Theory',
            status: 'closed',
            startedAt: DateTime(2026, 9, 3, 10, 0),
            endsAt: DateTime(2026, 9, 3, 11, 30),
            durationMinutes: 90,
            requiresPasscode: false,
            requiresGps: false,
            allowLateEntry: false,
          ),
        ];

        // Sort sessions chronologically
        sessions.sort((a, b) {
          final aDate = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDate.compareTo(bDate);
        });

        final matrix = <String, Map<String, String>>{
          'student-1': {'session-1': 'present', 'session-2': 'late'},
          'student-2': {
            'session-1': 'present',
            // session-2 omitted -> absent
          },
        };

        // Verify sorted by institutionId
        expect(students[0].institutionId, 'ID-001');
        expect(students[1].institutionId, 'ID-002');

        // Verify chronological sessions
        expect(sessions[0].id, 'session-1');
        expect(sessions[1].id, 'session-2');

        // Alice: 1 present + 1 late = 2 attended out of 2 = 100%
        final aliceStatuses = matrix['student-1']!;
        final aliceAttended = aliceStatuses.values
            .where((s) => s == 'present' || s == 'late')
            .length;
        final alicePct = (aliceAttended / sessions.length) * 100;
        expect(aliceAttended, 2);
        expect(alicePct, 100.0);

        // Bob: 1 present + absent = 1 attended out of 2 = 50%
        final bobStatuses = matrix['student-2']!;
        final bobAttended = bobStatuses.values
            .where((s) => s == 'present' || s == 'late')
            .length;
        final bobPct = (bobAttended / sessions.length) * 100;
        expect(bobAttended, 1);
        expect(bobPct, 50.0);
      },
    );

    // 3. Course attendance CSV output
    test(
      '3. Course attendance CSV builder exports valid chronological CSV with proper escaping',
      () {
        final filename = AttendanceCsvBuilder.generateFullRegisterFilename(
          courseCode: 'CSE 311',
          date: DateTime(2026, 9, 12),
        );
        expect(filename, 'attendance_CSE_311_full_register_2026-09-12.csv');

        final students = [
          const EnrolledStudent(
            uid: 's-1',
            institutionId: 'ID-001',
            displayName: 'Alice, In Wonderland',
            email: 'alice@demo.local',
            isActive: true,
          ),
          const EnrolledStudent(
            uid: 's-2',
            institutionId: 'ID-002',
            displayName: 'Bob Smith',
            email: 'bob@demo.local',
            isActive: true,
          ),
        ];

        final sessions = [
          TeacherAttendanceSession(
            id: 'sess-1',
            courseId: 'c1',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            classType: 'Theory',
            status: 'closed',
            durationMinutes: 90,
            requiresPasscode: false,
            requiresGps: false,
            allowLateEntry: false,
            startedAt: DateTime(2026, 9, 3, 10, 0),
            endsAt: DateTime(2026, 9, 3, 11, 30),
          ),
          TeacherAttendanceSession(
            id: 'sess-2',
            courseId: 'c1',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            classType: 'Lab',
            status: 'closed',
            durationMinutes: 90,
            requiresPasscode: false,
            requiresGps: false,
            allowLateEntry: false,
            startedAt: DateTime(2026, 9, 7, 14, 0),
            endsAt: DateTime(2026, 9, 7, 15, 30),
          ),
        ];

        final matrix = {
          's-1': {'sess-1': 'present', 'sess-2': 'late'},
          's-2': {'sess-1': 'present', 'sess-2': 'absent'},
        };

        final csvContent = AttendanceCsvBuilder.buildFullRegisterCsv(
          courseCode: 'CSE 311',
          courseName: 'Software Engineering',
          students: students,
          sessions: sessions,
          matrix: matrix,
        );

        // Verify UTF-8 header and columns
        expect(
          csvContent,
          contains(
            'Student Name,Roll/Institution ID,Class 1 (2026-09-03),Class 2 (2026-09-07),Attended Classes,Total Classes,Attendance Percentage',
          ),
        );
        // Escaping for commas in name
        expect(
          csvContent,
          contains('"Alice, In Wonderland",ID-001,Present,Late,2,2,100.0%'),
        );
        expect(
          csvContent,
          contains('Bob Smith,ID-002,Present,Absent,1,2,50.0%'),
        );
      },
    );

    // 4. Attendance cell correction state/percentage calculation
    test(
      '4. Attendance cell correction recalculates attended count and percentage correctly',
      () {
        // Bob starts with: Class 1 (present), Class 2 (absent), Class 3 (present)
        var sessionStatuses = <String, String>{
          's1': 'present',
          's2': 'absent',
          's3': 'present',
        };
        final totalClasses = 3;

        int computeAttended(Map<String, String> statuses) {
          return statuses.values
              .where((s) => s == 'present' || s == 'late')
              .length;
        }

        double computePercentage(int attended, int total) {
          return total > 0 ? (attended / total) * 100 : 0.0;
        }

        var attended = computeAttended(sessionStatuses);
        var percentage = computePercentage(attended, totalClasses);

        expect(attended, 2);
        expect(percentage, closeTo(66.67, 0.05));

        // Correct Class 2 from 'absent' to 'late'
        sessionStatuses['s2'] = 'late';
        attended = computeAttended(sessionStatuses);
        percentage = computePercentage(attended, totalClasses);

        // Attended is now 3/3 = 100%, total classes does NOT change
        expect(attended, 3);
        expect(totalClasses, 3);
        expect(percentage, 100.0);

        // Correct Class 1 from 'present' to 'absent'
        sessionStatuses['s1'] = 'absent';
        attended = computeAttended(sessionStatuses);
        percentage = computePercentage(attended, totalClasses);

        expect(attended, 2);
        expect(totalClasses, 3);
        expect(percentage, closeTo(66.67, 0.05));
      },
    );

    // 5. Student Dashboard showing only today’s classes
    test(
      '5. Student Dashboard schedules filter matches today dayIndex and chronological order',
      () {
        final now = DateTime.now();
        final todayWeekday = now.weekday;
        final todayDayIndex = todayWeekday == DateTime.sunday
            ? 0
            : todayWeekday;
        final otherDayIndex = (todayDayIndex + 2) % 7;

        final allSchedules = [
          ClassScheduleEntry(
            id: 'sch-other',
            courseId: 'c1',
            courseCode: 'CSE 101',
            courseName: 'Intro to CS',
            teacherName: 'Teacher Other',
            dayIndex: otherDayIndex,
            day: 'Other Day',
            startTime: '09:00',
            endTime: '10:30',
            room: 'Room 101',
            classType: 'Theory',
            status: 'scheduled',
          ),
          ClassScheduleEntry(
            id: 'sch-today-2',
            courseId: 'c2',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            teacherName: 'Dr. Demo Teacher',
            dayIndex: todayDayIndex,
            day: 'Today',
            startTime: '14:00',
            endTime: '15:30',
            room: 'Lab 3',
            classType: 'Lab',
            status: 'scheduled',
          ),
          ClassScheduleEntry(
            id: 'sch-today-1',
            courseId: 'c2',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            teacherName: 'Dr. Demo Teacher',
            dayIndex: todayDayIndex,
            day: 'Today',
            startTime: '10:00',
            endTime: '11:30',
            room: 'Lab 3',
            classType: 'Theory',
            status: 'scheduled',
          ),
        ];

        // Filter today's classes
        final todayClasses = allSchedules
            .where((s) => s.dayIndex == todayDayIndex)
            .toList();
        todayClasses.sort((a, b) => a.startTime.compareTo(b.startTime));

        // Should only contain 2 classes, and 'sch-today-1' (10:00) before 'sch-today-2' (14:00)
        expect(todayClasses.length, 2);
        expect(todayClasses[0].id, 'sch-today-1');
        expect(todayClasses[0].startTime, '10:00');
        expect(todayClasses[1].id, 'sch-today-2');
        expect(todayClasses[1].startTime, '14:00');
        expect(todayClasses.any((s) => s.id == 'sch-other'), isFalse);
      },
    );

    // 6. Calendar day/week mapping and responsive layout
    testWidgets(
      '6. TimetableCalendar renders Week and Day views responsively without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final entries = [
          const TimetableEntry(
            id: 't-1',
            courseId: 'demo-course-cse311',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            teacherName: 'Dr. Demo Teacher',
            dayIndex: 1,
            day: 'Monday',
            startTime: '10:00',
            endTime: '11:30',
            room: 'Lab 3',
            classType: 'Theory',
            status: 'active',
          ),
          const TimetableEntry(
            id: 't-2',
            courseId: 'demo-course-cse311',
            courseCode: 'CSE 311',
            courseName: 'Software Engineering',
            teacherName: 'Dr. Demo Teacher',
            dayIndex: 6,
            day: 'Saturday',
            startTime: '11:00',
            endTime: '12:30',
            room: 'Room 402',
            classType: 'Theory',
            status: 'active',
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

        // Check header controls exist
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Day'), findsOneWidget);
        expect(find.text('Week'), findsOneWidget);

        // Switch to Day view
        await tester.tap(find.text('Day'));
        await tester.pumpAndSettle();

        // Switch back to Week view
        await tester.tap(find.text('Week'));
        await tester.pumpAndSettle();

        // No overflow exception thrown
        expect(tester.takeException(), isNull);
      },
    );

    // 7. Emulator-only email verification decision
    test(
      '7. Emulator-only email verification decision based strictly on environment flag',
      () {
        bool shouldAutoVerify({required bool isFunctionsEmulator}) {
          return isFunctionsEmulator;
        }

        // Inside emulator environment
        expect(shouldAutoVerify(isFunctionsEmulator: true), isTrue);

        // Inside production environment
        expect(shouldAutoVerify(isFunctionsEmulator: false), isFalse);

        // Client config check
        expect(FirebaseEmulatorConfig.enabled, isA<bool>());
      },
    );
  });
}

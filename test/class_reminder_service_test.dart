import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/class_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.trackademic/notification_channel');
  final scheduledInvocations = <Map<String, dynamic>>[];
  final cancelledInvocations = <String>[];
  bool nativeShouldFail = false;

  setUp(() {
    scheduledInvocations.clear();
    cancelledInvocations.clear();
    nativeShouldFail = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'scheduleClassReminder') {
        if (nativeShouldFail) {
          return false;
        }
        scheduledInvocations.add(Map<String, dynamic>.from(call.arguments as Map));
        return true;
      } else if (call.method == 'cancelClassReminder') {
        cancelledInvocations.add((call.arguments as Map)['scheduleId'] as String);
        return true;
      } else if (call.method == 'cancelAllClassReminders') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ClassReminderService Focused Unit Tests', () {
    test('Calculates next occurrence and 15-minute advance reminder correctly', () async {
      final service = ClassReminderService();

      final schedule = ClassScheduleEntry(
        id: 'sched_1',
        courseId: 'cse101',
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        teacherName: 'Dr. Rahman',
        dayIndex: DateTime.now().weekday, // today
        day: 'Today',
        startTime: '23:59',
        endTime: '23:59',
        room: 'Lab 2',
        classType: 'Theory',
        status: 'active',
      );

      await service.syncScheduleReminders([schedule]);

      expect(service.activeReminders.length, 1);
      final reminder = service.activeReminders.first;
      expect(reminder.courseCode, 'CSE 101');
      expect(reminder.room, 'Lab 2');
      expect(reminder.nextOccurrence.isAfter(DateTime.now()), isTrue);
      expect(
        reminder.nextOccurrence.difference(reminder.reminderTime).inMinutes,
        15,
      );
      expect(scheduledInvocations.length, 1);
      expect(scheduledInvocations.first['scheduleId'], 'sched_1');
      expect(scheduledInvocations.first['dayOfWeek'], DateTime.now().weekday);
      expect(scheduledInvocations.first['leadMinutes'], 15);
    });

    test('Weekly recurrence: schedules 7 days later if current class reminder time has passed', () async {
      final service = ClassReminderService();

      // Class today at 00:01 (which has definitely passed today)
      final schedule = ClassScheduleEntry(
        id: 'sched_passed_today',
        courseId: 'cse102',
        courseCode: 'CSE 102',
        courseName: 'Data Structures',
        teacherName: 'Dr. Karim',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '00:01',
        endTime: '01:00',
        room: 'Lab 1',
        classType: 'Lab',
        status: 'active',
      );

      await service.syncScheduleReminders([schedule]);

      expect(service.activeReminders.length, 1);
      final reminder = service.activeReminders.first;
      // Must be scheduled for NEXT week (> 5 days in future)
      final diffDays = reminder.nextOccurrence.difference(DateTime.now()).inDays;
      expect(diffDays >= 6, isTrue);
      expect(reminder.reminderTime.isAfter(DateTime.now()), isTrue);
    });

    test('Aggregation across query chunks: chunk 1 does not cancel chunk 0 reminders', () async {
      final service = ClassReminderService();
      await service.cancelAllReminders();

      final scheduleChunk0 = ClassScheduleEntry(
        id: 'chunk0_sched',
        courseId: 'c_0',
        courseCode: 'C 0',
        courseName: 'Course 0',
        teacherName: 'T 0',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:58',
        endTime: '23:59',
        room: 'R0',
        classType: 'Theory',
        status: 'active',
      );

      final scheduleChunk1 = ClassScheduleEntry(
        id: 'chunk1_sched',
        courseId: 'c_1',
        courseCode: 'C 1',
        courseName: 'Course 1',
        teacherName: 'T 1',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:59',
        endTime: '23:59',
        room: 'R1',
        classType: 'Theory',
        status: 'active',
      );

      // Pass aggregated schedule list representing both chunks
      await service.syncScheduleReminders([scheduleChunk0, scheduleChunk1]);

      expect(service.activeReminders.length, 2);
      final ids = service.activeReminders.map((r) => r.scheduleId).toSet();
      expect(ids.contains('chunk0_sched'), isTrue);
      expect(ids.contains('chunk1_sched'), isTrue);

      // Now update with both chunks still intact
      await service.syncScheduleReminders([scheduleChunk0, scheduleChunk1]);
      expect(service.activeReminders.length, 2);
      // Ensure chunk0 was not cancelled
      expect(cancelledInvocations.contains('chunk0_sched'), isFalse);
    });

    test('Explicit native failure handling: does not retain reminder if native scheduling fails', () async {
      final service = ClassReminderService();
      await service.cancelAllReminders();

      nativeShouldFail = true;

      final schedule = ClassScheduleEntry(
        id: 'sched_fail_native',
        courseId: 'cse103',
        courseCode: 'CSE 103',
        courseName: 'Algorithms',
        teacherName: 'Dr. Ali',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:59',
        endTime: '23:59',
        room: 'Room 302',
        classType: 'Theory',
        status: 'active',
      );

      await service.syncScheduleReminders([schedule]);

      // Because native scheduling returned false, it must NOT be kept in activeReminders
      expect(service.activeReminders.isEmpty, isTrue);
    });

    test('Stale callback guard: rejects reminders from an outdated generation', () async {
      final service = ClassReminderService();
      await service.cancelAllReminders();

      final schedule = ClassScheduleEntry(
        id: 'stale_sched',
        courseId: 'cse104',
        courseCode: 'CSE 104',
        courseName: 'Database Systems',
        teacherName: 'Dr. Hasan',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:59',
        endTime: '23:59',
        room: 'Lab 4',
        classType: 'Theory',
        status: 'active',
      );

      // Sync with generation 999 (which is not current generation)
      await service.syncScheduleReminders([schedule], generation: 999);

      // Must have been discarded
      expect(service.activeReminders.isEmpty, isTrue);
    });

    test('Unenrollment: removing a schedule purges it and invokes cancel', () async {
      final service = ClassReminderService();
      await service.cancelAllReminders();

      final scheduleA = ClassScheduleEntry(
        id: 'sched_a',
        courseId: 'cse105',
        courseCode: 'CSE 105',
        courseName: 'Course A',
        teacherName: 'Teacher A',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:58',
        endTime: '23:59',
        room: 'Room A',
        classType: 'Theory',
        status: 'active',
      );

      await service.syncScheduleReminders([scheduleA]);
      expect(service.activeReminders.length, 1);

      // Unenroll / remove scheduleA
      await service.syncScheduleReminders([]);
      expect(service.activeReminders.isEmpty, isTrue);
      expect(cancelledInvocations.contains('sched_a'), isTrue);
    });
  });
}

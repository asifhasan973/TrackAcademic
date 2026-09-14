import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/class_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClassReminderService Unit Tests', () {
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
    });

    test('Ignores inactive or cancelled schedules', () async {
      final service = ClassReminderService();

      final schedule = ClassScheduleEntry(
        id: 'sched_cancelled',
        courseId: 'cse101',
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        teacherName: 'Dr. Rahman',
        dayIndex: DateTime.now().weekday,
        day: 'Today',
        startTime: '23:59',
        endTime: '23:59',
        room: 'Lab 2',
        classType: 'Theory',
        status: 'cancelled',
      );

      await service.syncScheduleReminders([schedule]);
      expect(service.activeReminders.isEmpty, isTrue);
    });

    test('cancelAllReminders clears memory and schedules', () async {
      final service = ClassReminderService();
      await service.cancelAllReminders();
      expect(service.activeReminders.isEmpty, isTrue);
    });
  });
}

import 'package:flutter/foundation.dart';
import 'academic_service.dart';

/// Represents a device-local scheduled reminder for an upcoming class.
/// Distinct from remote FCM push notifications: this operates locally on the device
/// based on the student's or teacher's confirmed weekly schedule.
class ScheduledClassReminder {
  final String scheduleId;
  final String courseCode;
  final String courseName;
  final String room;
  final String startTime;
  final DateTime nextOccurrence;
  final DateTime reminderTime;

  const ScheduledClassReminder({
    required this.scheduleId,
    required this.courseCode,
    required this.courseName,
    required this.room,
    required this.startTime,
    required this.nextOccurrence,
    required this.reminderTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'scheduleId': scheduleId,
      'courseCode': courseCode,
      'courseName': courseName,
      'room': room,
      'startTime': startTime,
      'nextOccurrence': nextOccurrence.toIso8601String(),
      'reminderTime': reminderTime.toIso8601String(),
      'type': 'device_local_scheduled_reminder',
    };
  }
}

/// Service managing device-local class timetable reminders.
///
/// Architecture note:
/// This service implements explicit zero-cost device-local scheduling without relying on
/// paid serverless schedulers or backend setTimeout loops. Reminders are recomputed whenever
/// timetable entries or course enrollment changes, and purged on account switch or logout.
class ClassReminderService {
  static final ClassReminderService _instance = ClassReminderService._internal();
  factory ClassReminderService() => _instance;
  ClassReminderService._internal();

  final Map<String, ScheduledClassReminder> _activeReminders = {};

  /// Current active scheduled reminders
  List<ScheduledClassReminder> get activeReminders =>
      List.unmodifiable(_activeReminders.values);

  /// Synchronize scheduled reminders with the current active schedule list.
  /// Replaces existing reminders, removes deleted schedules, and computes next trigger times.
  void syncScheduleReminders(List<ClassScheduleEntry> schedules) {
    _activeReminders.clear();
    final now = DateTime.now();

    for (final schedule in schedules) {
      if (schedule.status != 'active') continue;

      final nextClass = _computeNextOccurrence(
        targetWeekday: schedule.dayIndex,
        timeString: schedule.startTime,
        referenceTime: now,
      );

      if (nextClass == null) continue;

      // Reminder fires 15 minutes before scheduled class start
      final reminderTime = nextClass.subtract(const Duration(minutes: 15));
      if (reminderTime.isAfter(now)) {
        final reminder = ScheduledClassReminder(
          scheduleId: schedule.id,
          courseCode: schedule.courseCode,
          courseName: schedule.courseName,
          room: schedule.room,
          startTime: schedule.startTime,
          nextOccurrence: nextClass,
          reminderTime: reminderTime,
        );
        _activeReminders[schedule.id] = reminder;
      }
    }

    debugPrint(
      '[ClassReminderService] Synchronized ${_activeReminders.length} device-local class reminders.',
    );
  }

  /// Cancels all scheduled local reminders (e.g. on sign out or enrollment change).
  void cancelAllReminders() {
    _activeReminders.clear();
    debugPrint('[ClassReminderService] Cancelled all device-local reminders.');
  }

  /// Computes the next upcoming DateTime for a class given weekday (1=Mon ... 7=Sun) and 'HH:mm'
  DateTime? _computeNextOccurrence({
    required int targetWeekday,
    required String timeString,
    required DateTime referenceTime,
  }) {
    final parts = timeString.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    var daysUntil = (targetWeekday - referenceTime.weekday) % 7;
    if (daysUntil == 0) {
      final todayClassTime = DateTime(
        referenceTime.year,
        referenceTime.month,
        referenceTime.day,
        hour,
        minute,
      );
      if (todayClassTime.isBefore(referenceTime)) {
        daysUntil = 7; // Next week
      }
    }

    return DateTime(
      referenceTime.year,
      referenceTime.month,
      referenceTime.day + daysUntil,
      hour,
      minute,
    );
  }
}

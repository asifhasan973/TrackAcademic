import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'academic_service.dart';

/// Represents a device-local scheduled reminder for an upcoming class.
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

/// Service managing device-local class timetable reminders using Android AlarmManager.
///
/// Operates on zero-cost principles by utilizing device-local alarms rather than paid
/// serverless schedulers. Subscribes to authorized timetable streams for active enrollments/courses,
/// updates or cancels schedules upon changes and logout, and leverages native Android receivers
/// for device reboot and timezone adjustments.
class ClassReminderService {
  static final ClassReminderService _instance = ClassReminderService._internal();
  factory ClassReminderService() => _instance;
  ClassReminderService._internal();

  static const MethodChannel _channel = MethodChannel('com.trackademic/notification_channel');
  FirebaseFirestore get _database => FirebaseFirestore.instance;

  final Map<String, ScheduledClassReminder> _activeReminders = {};
  StreamSubscription? _coursesSubscription;
  final List<StreamSubscription> _scheduleSubscriptions = [];
  String? _activeUserId;

  /// Current active scheduled reminders in memory
  List<ScheduledClassReminder> get activeReminders =>
      List.unmodifiable(_activeReminders.values);

  /// Starts listening to timetable streams for the authorized user and their enrolled/taught courses.
  void startScheduleSync(String userId, String role) {
    if (_activeUserId == userId && _coursesSubscription != null) {
      return;
    }

    stopScheduleSync();
    _activeUserId = userId;

    try {
      if (role.toLowerCase() == 'teacher') {
        _coursesSubscription = _database
            .collection('courses')
            .where('teacherId', isEqualTo: userId)
            .snapshots()
            .listen(
          (courseSnap) {
            final courseIds = courseSnap.docs
                .where((d) => d.data()['isActive'] == true)
                .map((d) => d.id)
                .toList();
            _listenToSchedules(courseIds);
          },
          onError: (e) => debugPrint('[ClassReminderService] Teacher course stream error: $e'),
        );
      } else {
        // Student: fetch enrolled courses and listen
        _coursesSubscription = _database
            .collection('courses')
            .where('studentIds', arrayContains: userId)
            .snapshots()
            .listen(
          (courseSnap) {
            final courseIds = courseSnap.docs
                .where((d) => d.data()['isActive'] == true)
                .map((d) => d.id)
                .toList();
            _listenToSchedules(courseIds);
          },
          onError: (e) {
            // Fallback via AcademicService
            AcademicService().loadCurrentCourseIds().then((ids) {
              _listenToSchedules(ids);
            }).catchError((_) {});
          },
        );
      }
      debugPrint('[ClassReminderService] Started timetable stream sync for $userId ($role)');
    } catch (e) {
      debugPrint('[ClassReminderService] Error starting schedule sync: $e');
    }
  }

  void _listenToSchedules(List<String> courseIds) {
    for (final sub in _scheduleSubscriptions) {
      sub.cancel();
    }
    _scheduleSubscriptions.clear();

    if (courseIds.isEmpty) {
      syncScheduleReminders([]);
      return;
    }

    // Chunk courseIds into batches of 10 for Firestore 'whereIn' constraints
    for (var i = 0; i < courseIds.length; i += 10) {
      final chunk = courseIds.sublist(i, i + 10 > courseIds.length ? courseIds.length : i + 10);
      final sub = _database
          .collection('schedules')
          .where('courseId', whereIn: chunk)
          .snapshots()
          .listen(
        (snap) {
          final entries = snap.docs
              .map((d) => ClassScheduleEntry.fromMap(d.id, d.data()))
              .toList();
          syncScheduleReminders(entries);
        },
        onError: (e) => debugPrint('[ClassReminderService] Schedule query error: $e'),
      );
      _scheduleSubscriptions.add(sub);
    }
  }

  /// Stops timetable sync and cancels all subscriptions and reminders (e.g. on logout).
  void stopScheduleSync() {
    _coursesSubscription?.cancel();
    _coursesSubscription = null;

    for (final sub in _scheduleSubscriptions) {
      sub.cancel();
    }
    _scheduleSubscriptions.clear();

    cancelAllReminders();
    _activeUserId = null;
    debugPrint('[ClassReminderService] Timetable sync stopped.');
  }

  /// Synchronize scheduled reminders with active schedule entries.
  /// Schedules real Android system alarms and purges deleted or expired ones.
  Future<void> syncScheduleReminders(List<ClassScheduleEntry> schedules) async {
    final now = DateTime.now();
    final newScheduleIds = <String>{};

    for (final schedule in schedules) {
      if (schedule.status != 'active' && schedule.status != 'scheduled') continue;
      newScheduleIds.add(schedule.id);

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

        // Dispatch real Android alarm scheduling
        if (!kIsWeb) {
          try {
            await _channel.invokeMethod('scheduleClassReminder', {
              'scheduleId': schedule.id,
              'courseCode': schedule.courseCode,
              'courseName': schedule.courseName,
              'room': schedule.room,
              'startTime': schedule.startTime,
              'triggerTimeMillis': reminderTime.millisecondsSinceEpoch,
            });
          } catch (e) {
            debugPrint('[ClassReminderService] Native alarm invocation failed: $e');
          }
        }
      }
    }

    // Cancel any deleted/removed schedules
    final removedIds = _activeReminders.keys.where((k) => !newScheduleIds.contains(k)).toList();
    for (final removedId in removedIds) {
      _activeReminders.remove(removedId);
      if (!kIsWeb) {
        try {
          await _channel.invokeMethod('cancelClassReminder', {'scheduleId': removedId});
        } catch (_) {}
      }
    }

    debugPrint(
      '[ClassReminderService] Synchronized ${_activeReminders.length} active device-local class reminders.',
    );
  }

  /// Cancels all scheduled local reminders (e.g. on sign out or enrollment change).
  Future<void> cancelAllReminders() async {
    _activeReminders.clear();
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('cancelAllClassReminders');
      } catch (e) {
        debugPrint('[ClassReminderService] Failed to cancel native alarms: $e');
      }
    }
    debugPrint('[ClassReminderService] Cancelled all device-local reminders.');
  }

  /// Schedules an immediate test reminder on the device (default: 5 seconds in future)
  /// to verify native AlarmManager invocation and notification delivery on Android.
  Future<bool> scheduleInstantTestReminder({
    Duration delay = const Duration(seconds: 5),
    String courseCode = 'CSE 101',
    String courseName = 'Introduction to Computer Science',
    String room = 'Lab 3',
  }) async {
    if (kIsWeb) return false;
    try {
      final triggerTime = DateTime.now().add(delay);
      final ok = await _channel.invokeMethod<bool>('scheduleClassReminder', {
        'scheduleId': 'test_schedule_${DateTime.now().millisecondsSinceEpoch}',
        'courseCode': courseCode,
        'courseName': courseName,
        'room': room,
        'startTime': 'Now',
        'triggerTimeMillis': triggerTime.millisecondsSinceEpoch,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[ClassReminderService] scheduleInstantTestReminder failed: $e');
      return false;
    }
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
    if (daysUntil < 0) daysUntil += 7;

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

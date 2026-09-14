import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'academic_service.dart';

/// Represents a device-local scheduled reminder for an upcoming class.
class ScheduledClassReminder {
  final String scheduleId;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String room;
  final String startTime;
  final int dayIndex;
  final DateTime nextOccurrence;
  final DateTime reminderTime;

  const ScheduledClassReminder({
    required this.scheduleId,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.room,
    required this.startTime,
    required this.dayIndex,
    required this.nextOccurrence,
    required this.reminderTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'scheduleId': scheduleId,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseName': courseName,
      'room': room,
      'startTime': startTime,
      'dayIndex': dayIndex,
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
/// for device reboot, timezone adjustments, and subsequent weekly occurrences.
class ClassReminderService {
  static final ClassReminderService _instance = ClassReminderService._internal();
  factory ClassReminderService() => _instance;
  ClassReminderService._internal();

  static const MethodChannel _channel = MethodChannel('com.trackademic/notification_channel');
  FirebaseFirestore get _database => FirebaseFirestore.instance;

  final Map<String, ScheduledClassReminder> _activeReminders = {};
  final Map<int, List<ClassScheduleEntry>> _chunkSchedules = {};
  final Map<String, StreamSubscription> _courseDocSubscriptions = {};
  final Map<String, bool> _courseActiveMap = {};

  StreamSubscription? _userSubscription;
  StreamSubscription? _coursesSubscription;
  final List<StreamSubscription> _scheduleSubscriptions = [];
  String? _activeUserId;
  int _syncGeneration = 0;

  /// Current active scheduled reminders in memory
  List<ScheduledClassReminder> get activeReminders =>
      List.unmodifiable(_activeReminders.values);

  /// Starts listening to timetable streams for the authorized user and their enrolled/taught courses.
  void startScheduleSync(String userId, String role) {
    if (_activeUserId == userId && (_coursesSubscription != null || _userSubscription != null)) {
      return;
    }

    final currentGen = ++_syncGeneration;
    _activeUserId = userId;
    _cancelInternalSubscriptions();

    try {
      if (role.toLowerCase() == 'teacher') {
        // Teachers have permission to list/query courses where teacherId == userId
        _coursesSubscription = _database
            .collection('courses')
            .where('teacherId', isEqualTo: userId)
            .snapshots()
            .listen(
          (courseSnap) {
            if (_syncGeneration != currentGen || _activeUserId != userId) return;
            final courseIds = courseSnap.docs
                .where((d) => d.data()['isActive'] == true)
                .map((d) => d.id)
                .toList();
            _listenToSchedules(courseIds, currentGen);
          },
          onError: (e) => debugPrint('[ClassReminderService] Teacher course stream error: $e'),
        );
      } else {
        // Students: cannot list `/courses`. Read authorized profile at `users/{userId}` to obtain enrolled courseIds.
        _userSubscription = _database
            .collection('users')
            .doc(userId)
            .snapshots()
            .listen(
          (userSnap) {
            if (_syncGeneration != currentGen || _activeUserId != userId) return;
            final data = userSnap.data();
            final rawCourseIds = data?['courseIds'];
            final enrolledIds = (rawCourseIds is List)
                ? rawCourseIds
                    .whereType<String>()
                    .map((id) => id.trim())
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .toList()
                : <String>[];

            _updateStudentCourseListeners(enrolledIds, currentGen);
          },
          onError: (e) {
            debugPrint('[ClassReminderService] User profile stream error: $e');
            // Fallback via AcademicService
            AcademicService().loadCurrentCourseIds().then((ids) {
              if (_syncGeneration == currentGen && _activeUserId == userId) {
                _updateStudentCourseListeners(ids, currentGen);
              }
            }).catchError((_) {});
          },
        );
      }
      debugPrint('[ClassReminderService] Started timetable stream sync for $userId ($role, gen $currentGen)');
    } catch (e) {
      debugPrint('[ClassReminderService] Error starting schedule sync: $e');
    }
  }

  void _updateStudentCourseListeners(List<String> enrolledIds, int generation) {
    if (_syncGeneration != generation || _activeUserId == null) return;

    // Cancel subscriptions for courses that student unenrolled from
    final enrolledSet = enrolledIds.toSet();
    final toRemove = _courseDocSubscriptions.keys.where((id) => !enrolledSet.contains(id)).toList();
    for (final id in toRemove) {
      _courseDocSubscriptions[id]?.cancel();
      _courseDocSubscriptions.remove(id);
      _courseActiveMap.remove(id);
    }

    if (enrolledIds.isEmpty) {
      _listenToSchedules([], generation);
      return;
    }

    // Subscribe to individual permitted course documents to observe archive/active changes
    for (final courseId in enrolledIds) {
      if (!_courseDocSubscriptions.containsKey(courseId)) {
        final sub = _database
            .collection('courses')
            .doc(courseId)
            .snapshots()
            .listen(
          (docSnap) {
            if (_syncGeneration != generation) return;
            final isActive = docSnap.exists && (docSnap.data()?['isActive'] == true);
            _courseActiveMap[courseId] = isActive;

            // Compute active permitted courses
            final activeIds = enrolledIds.where((id) => _courseActiveMap[id] == true).toList();
            _listenToSchedules(activeIds, generation);
          },
          onError: (e) {
            debugPrint('[ClassReminderService] Course doc stream error ($courseId): $e');
            // Assume active if error occurs or fallback
            _courseActiveMap[courseId] = true;
            final activeIds = enrolledIds.where((id) => _courseActiveMap[id] != false).toList();
            _listenToSchedules(activeIds, generation);
          },
        );
        _courseDocSubscriptions[courseId] = sub;
      }
    }

    // Trigger initial schedule fetch with whatever active courses are already known
    final activeIds = enrolledIds.where((id) => _courseActiveMap[id] != false).toList();
    _listenToSchedules(activeIds, generation);
  }

  void _listenToSchedules(List<String> courseIds, int generation) {
    for (final sub in _scheduleSubscriptions) {
      sub.cancel();
    }
    _scheduleSubscriptions.clear();
    _chunkSchedules.clear();

    if (courseIds.isEmpty) {
      syncScheduleReminders([], generation: generation);
      return;
    }

    // Chunk courseIds into batches of 10 for Firestore 'whereIn' constraints
    for (var i = 0; i < courseIds.length; i += 10) {
      final chunkIndex = i ~/ 10;
      final chunk = courseIds.sublist(i, i + 10 > courseIds.length ? courseIds.length : i + 10);
      final sub = _database
          .collection('schedules')
          .where('courseId', whereIn: chunk)
          .snapshots()
          .listen(
        (snap) {
          if (_syncGeneration != generation || _activeUserId == null) return;
          final entries = snap.docs
              .map((d) => ClassScheduleEntry.fromMap(d.id, d.data()))
              .toList();

          // Aggregate schedule snapshots across all query chunks before reconciliation.
          // One chunk must never cancel another chunk's reminders.
          _chunkSchedules[chunkIndex] = entries;
          _reconcileAggregatedChunks(generation);
        },
        onError: (e) => debugPrint('[ClassReminderService] Schedule query chunk $chunkIndex error: $e'),
      );
      _scheduleSubscriptions.add(sub);
    }
  }

  void _reconcileAggregatedChunks(int generation) {
    if (_syncGeneration != generation || _activeUserId == null) return;

    // Flatten all schedules from active chunks
    final aggregated = <ClassScheduleEntry>[];
    for (final chunkEntries in _chunkSchedules.values) {
      aggregated.addAll(chunkEntries);
    }

    syncScheduleReminders(aggregated, generation: generation);
  }

  void _cancelInternalSubscriptions() {
    _coursesSubscription?.cancel();
    _coursesSubscription = null;

    _userSubscription?.cancel();
    _userSubscription = null;

    for (final sub in _courseDocSubscriptions.values) {
      sub.cancel();
    }
    _courseDocSubscriptions.clear();
    _courseActiveMap.clear();

    for (final sub in _scheduleSubscriptions) {
      sub.cancel();
    }
    _scheduleSubscriptions.clear();
    _chunkSchedules.clear();
  }

  /// Stops timetable sync and cancels all subscriptions and reminders (e.g. on logout).
  Future<void> stopScheduleSync() async {
    _syncGeneration++;
    _cancelInternalSubscriptions();
    _activeUserId = null;
    await cancelAllReminders();
    debugPrint('[ClassReminderService] Timetable sync stopped and all reminders cancelled.');
  }

  /// Synchronize scheduled reminders with active schedule entries.
  /// Schedules real Android system alarms and purges deleted, un-enrolled, or cancelled ones.
  Future<void> syncScheduleReminders(
    List<ClassScheduleEntry> schedules, {
    int? generation,
  }) async {
    final effectiveGen = generation ?? _syncGeneration;
    if (effectiveGen != _syncGeneration) {
      debugPrint('[ClassReminderService] Discarding stale sync callback (gen $effectiveGen != current $_syncGeneration)');
      return;
    }

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
          courseId: schedule.courseId,
          courseCode: schedule.courseCode,
          courseName: schedule.courseName,
          room: schedule.room,
          startTime: schedule.startTime,
          dayIndex: schedule.dayIndex,
          nextOccurrence: nextClass,
          reminderTime: reminderTime,
        );

        bool scheduledNatively = true;

        // Dispatch real Android alarm scheduling
        if (!kIsWeb) {
          try {
            final ok = await _channel.invokeMethod<bool>('scheduleClassReminder', {
              'scheduleId': schedule.id,
              'courseId': schedule.courseId,
              'userId': _activeUserId ?? '',
              'courseCode': schedule.courseCode,
              'courseName': schedule.courseName,
              'room': schedule.room,
              'startTime': schedule.startTime,
              'dayOfWeek': schedule.dayIndex,
              'leadMinutes': 15,
              'triggerTimeMillis': reminderTime.millisecondsSinceEpoch,
            });
            scheduledNatively = ok ?? false;
            if (!scheduledNatively) {
              debugPrint('[ClassReminderService] Native alarm returned false for ${schedule.id}');
            }
          } catch (e) {
            scheduledNatively = false;
            debugPrint('[ClassReminderService] Native alarm invocation failed for ${schedule.id}: $e');
          }
        }

        // Guard against state changes during async native channel invocation
        if (effectiveGen != _syncGeneration) return;

        if (scheduledNatively) {
          _activeReminders[schedule.id] = reminder;
        } else {
          _activeReminders.remove(schedule.id);
        }
      }
    }

    // Cancel any deleted/removed/unenrolled schedules
    final removedIds = _activeReminders.keys.where((k) => !newScheduleIds.contains(k)).toList();
    for (final removedId in removedIds) {
      _activeReminders.remove(removedId);
      if (!kIsWeb) {
        try {
          await _channel.invokeMethod('cancelClassReminder', {'scheduleId': removedId});
        } catch (e) {
          debugPrint('[ClassReminderService] Native cancel failed for $removedId: $e');
        }
      }
    }

    debugPrint(
      '[ClassReminderService] Synchronized ${_activeReminders.length} active device-local class reminders (gen $effectiveGen).',
    );
  }

  /// Cancels all scheduled local reminders (e.g. on sign out or enrollment change).
  Future<void> cancelAllReminders() async {
    _activeReminders.clear();
    _chunkSchedules.clear();
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
        'courseId': 'test_course',
        'userId': _activeUserId ?? '',
        'courseCode': courseCode,
        'courseName': courseName,
        'room': room,
        'startTime': 'Now',
        'dayOfWeek': -1, // Non-recurring test
        'leadMinutes': 0,
        'triggerTimeMillis': triggerTime.millisecondsSinceEpoch,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[ClassReminderService] scheduleInstantTestReminder failed: $e');
      return false;
    }
  }

  /// Computes the next upcoming DateTime for a class given weekday (1=Mon ... 7=Sun) and 'HH:mm'.
  /// Recalculates timezone-aware next occurrence, advancing by 7 days if the reminder time
  /// for the current week has already passed.
  DateTime? _computeNextOccurrence({
    required int targetWeekday,
    required String timeString,
    required DateTime referenceTime,
    int leadMinutes = 15,
  }) {
    final parts = timeString.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    var daysUntil = (targetWeekday - referenceTime.weekday) % 7;
    if (daysUntil < 0) daysUntil += 7;

    final candidate = DateTime(
      referenceTime.year,
      referenceTime.month,
      referenceTime.day + daysUntil,
      hour,
      minute,
    );

    // If the reminder trigger time (candidate - leadMinutes) has already passed,
    // schedule for the subsequent weekly occurrence.
    final candidateReminder = candidate.subtract(Duration(minutes: leadMinutes));
    if (!candidateReminder.isAfter(referenceTime)) {
      return candidate.add(const Duration(days: 7));
    }

    return candidate;
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class StudentAcademicService {
  const StudentAcademicService();

  FirebaseFirestore get _database => FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw const StudentAcademicServiceException('You are not signed in.');
    }

    return user.uid;
  }

  Future<void> requestJoinCourse(String joinCode) async {
    await _call('requestJoinCourse', {
      'joinCode': joinCode.trim().toUpperCase(),
    });
  }

  Future<List<StudentAttendanceSession>> loadActiveSessions() async {
    final profile = await _database.collection('users').doc(_uid).get();

    final rawCourseIds = profile.data()?['courseIds'];

    if (rawCourseIds is! List) {
      return const [];
    }

    final courseIds = rawCourseIds
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final sessions = <StudentAttendanceSession>[];

    for (final courseId in courseIds) {
      final snapshot = await _database
          .collection('attendanceSessions')
          .where('courseId', isEqualTo: courseId)
          .get();

      for (final document in snapshot.docs) {
        final session = StudentAttendanceSession.fromMap(
          document.id,
          document.data(),
        );

        if (session.status == 'active') {
          sessions.add(session);
        }
      }
    }

    sessions.sort((first, second) {
      final firstEnd = first.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final secondEnd = second.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return firstEnd.compareTo(secondEnd);
    });

    return sessions;
  }

  Future<List<StudentAttendanceRecord>> loadMyAttendanceRecords() async {
    final uid = _uid;

    final profile = await _database.collection('users').doc(uid).get();

    final rawCourseIds = profile.data()?['courseIds'];

    if (rawCourseIds is! List) {
      return const [];
    }

    final records = <StudentAttendanceRecord>[];

    for (final courseId in rawCourseIds.whereType<String>()) {
      final snapshot = await _database
          .collection('attendanceRecords')
          .where('courseId', isEqualTo: courseId)
          .where('studentId', isEqualTo: uid)
          .get();

      records.addAll(
        snapshot.docs.map(
          (document) =>
              StudentAttendanceRecord.fromMap(document.id, document.data()),
        ),
      );
    }

    records.sort((first, second) {
      final firstTime =
          first.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final secondTime =
          second.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return secondTime.compareTo(firstTime);
    });

    return records;
  }

  Future<void> submitAttendance({
    required StudentAttendanceSession session,
    required String? passcode,
  }) async {
    double? latitude;
    double? longitude;

    if (session.requiresGps) {
      final position = await _getCurrentPosition();

      latitude = position.latitude;
      longitude = position.longitude;
    }

    await _call('submitAttendance', {
      'sessionId': session.id,
      'passcode': passcode,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<Position> _getCurrentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      throw const StudentAcademicServiceException(
        'Location services are disabled.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const StudentAcademicServiceException(
        'Location permission is required for this attendance session.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const StudentAcademicServiceException(
        'Location permission is blocked in your browser or device settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(name)
          .call<Map<String, dynamic>>(data);

      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw StudentAcademicServiceException(
        error.message ?? 'The operation failed.',
      );
    }
  }
}

class StudentAttendanceSession {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String classType;
  final String status;
  final bool requiresPasscode;
  final bool requiresGps;
  final bool allowLateEntry;
  final DateTime? startedAt;
  final DateTime? endsAt;

  const StudentAttendanceSession({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.classType,
    required this.status,
    required this.requiresPasscode,
    required this.requiresGps,
    required this.allowLateEntry,
    required this.startedAt,
    required this.endsAt,
  });

  factory StudentAttendanceSession.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime? toDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }

      return null;
    }

    return StudentAttendanceSession(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      classType: data['classType'] as String? ?? '',
      status: data['status'] as String? ?? '',
      requiresPasscode: data['requiresPasscode'] as bool? ?? false,
      requiresGps: data['requiresGps'] as bool? ?? false,
      allowLateEntry: data['allowLateEntry'] as bool? ?? false,
      startedAt: toDate(data['startedAt']),
      endsAt: toDate(data['endsAt']),
    );
  }
}

class StudentAttendanceRecord {
  final String id;
  final String courseCode;
  final String courseName;
  final String status;
  final String source;
  final DateTime? markedAt;

  const StudentAttendanceRecord({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.status,
    required this.source,
    required this.markedAt,
  });

  factory StudentAttendanceRecord.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawMarkedAt = data['markedAt'];

    return StudentAttendanceRecord(
      id: id,
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      status: data['status'] as String? ?? '',
      source: data['source'] as String? ?? '',
      markedAt: rawMarkedAt is Timestamp ? rawMarkedAt.toDate() : null,
    );
  }
}

class StudentAcademicServiceException implements Exception {
  final String message;

  const StudentAcademicServiceException(this.message);

  @override
  String toString() => message;
}

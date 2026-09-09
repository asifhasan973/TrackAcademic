import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TeacherAcademicService {
  const TeacherAcademicService();

  FirebaseFirestore get _database => FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  String get currentTeacherName {
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();

    if (name == null || name.isEmpty) {
      return 'Teacher';
    }

    return name;
  }

  String get _teacherId {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw const TeacherAcademicServiceException('You are not signed in.');
    }

    return user.uid;
  }

  Future<List<TeacherCourse>> loadMyCourses() async {
    final snapshot = await _database
        .collection('courses')
        .where('teacherId', isEqualTo: _teacherId)
        .get();

    final courses = snapshot.docs
        .map((document) => TeacherCourse.fromMap(document.id, document.data()))
        .where((course) => course.isActive)
        .toList();

    courses.sort((first, second) => first.code.compareTo(second.code));

    return courses;
  }

  Future<String> createCourse({
    required String code,
    required String name,
    String? department,
    String? batch,
    String? section,
    String? semester,
    String? room,
  }) async {
    final data = await _call('createCourse', {
      'code': code,
      'name': name,
      'department': department,
      'batch': batch,
      'section': section,
      'semester': semester,
      'room': room,
    });

    return data['courseId'] as String;
  }

  Future<void> enrollStudent({
    required String courseId,
    required String institutionId,
  }) async {
    await _call('enrollStudent', {
      'courseId': courseId,
      'institutionId': institutionId,
    });
  }

  Future<void> unenrollStudent({
    required String courseId,
    required String studentId,
  }) async {
    await _call('unenrollStudent', {
      'courseId': courseId,
      'studentId': studentId,
    });
  }

  Future<List<EnrolledStudent>> loadCourseStudents(String courseId) async {
    final snapshot = await _database
        .collection('courses')
        .doc(courseId)
        .collection('students')
        .get();

    final students = snapshot.docs
        .map(
          (document) => EnrolledStudent.fromMap(document.id, document.data()),
        )
        .where((student) => student.isActive)
        .toList();

    students.sort(
      (first, second) => first.institutionId.compareTo(second.institutionId),
    );

    return students;
  }

  Future<List<TeacherScheduleEntry>> loadMySchedules() async {
    final courses = await loadMyCourses();

    final entries = <TeacherScheduleEntry>[];

    for (final course in courses) {
      final snapshot = await _database
          .collection('schedules')
          .where('courseId', isEqualTo: course.id)
          .get();

      entries.addAll(
        snapshot.docs.map(
          (document) =>
              TeacherScheduleEntry.fromMap(document.id, document.data()),
        ),
      );
    }

    entries.sort((first, second) {
      final day = first.dayIndex.compareTo(second.dayIndex);

      if (day != 0) {
        return day;
      }

      return first.startTime.compareTo(second.startTime);
    });

    return entries;
  }

  Future<void> createSchedule({
    required String courseId,
    required int dayIndex,
    required String day,
    required String startTime,
    required String endTime,
    required String room,
    required String classType,
  }) async {
    await _call('createSchedule', {
      'courseId': courseId,
      'dayIndex': dayIndex,
      'day': day,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'classType': classType,
    });
  }

  Future<void> updateSchedule({
    required String scheduleId,
    required String courseId,
    required int dayIndex,
    required String day,
    required String startTime,
    required String endTime,
    required String room,
    required String classType,
  }) async {
    await _call('updateSchedule', {
      'scheduleId': scheduleId,
      'courseId': courseId,
      'dayIndex': dayIndex,
      'day': day,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'classType': classType,
    });
  }

  Future<void> deleteSchedule(String scheduleId) async {
    await _call('deleteSchedule', {'scheduleId': scheduleId});
  }

  Future<List<TeacherAttendanceSession>> loadAttendanceSessions() async {
    final courses = await loadMyCourses();

    final sessions = <TeacherAttendanceSession>[];

    for (final course in courses) {
      final snapshot = await _database
          .collection('attendanceSessions')
          .where('courseId', isEqualTo: course.id)
          .get();

      sessions.addAll(
        snapshot.docs.map(
          (document) =>
              TeacherAttendanceSession.fromMap(document.id, document.data()),
        ),
      );
    }

    sessions.sort((first, second) {
      final firstTime =
          first.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final secondTime =
          second.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      return secondTime.compareTo(firstTime);
    });

    return sessions;
  }

  Future<void> createAttendanceSession({
    required String courseId,
    required String classType,
    required int durationMinutes,
    required bool requiresPasscode,
    required String? passcode,
    required bool requiresGps,
    required double? latitude,
    required double? longitude,
    required double? radiusMeters,
    required bool allowLateEntry,
  }) async {
    await _call('createAttendanceSession', {
      'courseId': courseId,
      'classType': classType,
      'durationMinutes': durationMinutes,
      'requiresPasscode': requiresPasscode,
      'passcode': passcode,
      'requiresGps': requiresGps,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'allowLateEntry': allowLateEntry,
    });
  }

  Future<void> closeAttendanceSession(String sessionId) async {
    await _call('closeAttendanceSession', {'sessionId': sessionId});
  }

  Future<List<TeacherAttendanceRecord>> loadAttendanceRecords(
    TeacherAttendanceSession session,
  ) async {
    final snapshot = await _database
        .collection('attendanceRecords')
        .where('courseId', isEqualTo: session.courseId)
        .where('sessionId', isEqualTo: session.id)
        .get();

    final records = snapshot.docs
        .map(
          (document) =>
              TeacherAttendanceRecord.fromMap(document.id, document.data()),
        )
        .toList();

    records.sort(
      (first, second) => first.institutionId.compareTo(second.institutionId),
    );

    return records;
  }

  Future<List<TeacherAssessment>> loadAssessmentsForCourse(
    String courseId,
  ) async {
    final snapshot = await _database
        .collection('assessments')
        .where('courseId', isEqualTo: courseId)
        .get();

    final assessments = snapshot.docs
        .map(
          (document) => TeacherAssessment.fromMap(document.id, document.data()),
        )
        .toList();

    assessments.sort((first, second) => first.name.compareTo(second.name));

    return assessments;
  }

  Future<List<TeacherAssessment>> loadAllAssessments() async {
    final courses = await loadMyCourses();

    final result = <TeacherAssessment>[];

    for (final course in courses) {
      result.addAll(await loadAssessmentsForCourse(course.id));
    }

    return result;
  }

  Future<void> createAssessment({
    required String courseId,
    required String name,
    required double maxScore,
  }) async {
    await _call('createAssessment', {
      'courseId': courseId,
      'name': name,
      'maxScore': maxScore,
    });
  }

  Future<List<TeacherMark>> loadAssessmentMarks(
    TeacherAssessment assessment,
  ) async {
    final snapshot = await _database
        .collection('marks')
        .where('courseId', isEqualTo: assessment.courseId)
        .where('assessmentId', isEqualTo: assessment.id)
        .get();

    return snapshot.docs
        .map((document) => TeacherMark.fromMap(document.id, document.data()))
        .toList();
  }

  Future<void> saveAssessmentMarks({
    required String assessmentId,
    required Map<String, double> marks,
  }) async {
    await _call('saveAssessmentMarks', {
      'assessmentId': assessmentId,
      'marks': marks.entries
          .map((entry) => {'studentId': entry.key, 'score': entry.value})
          .toList(),
    });
  }

  Future<void> publishAssessment(String assessmentId) async {
    await _call('publishAssessment', {'assessmentId': assessmentId});
  }

  Future<TeacherDashboardOverview> loadDashboardOverview() async {
    final courses = await loadMyCourses();

    var studentEnrollments = 0;

    for (final course in courses) {
      final students = await loadCourseStudents(course.id);

      studentEnrollments += students.length;
    }

    final schedules = await loadMySchedules();

    final sessions = await loadAttendanceSessions();

    final assessments = await loadAllAssessments();

    return TeacherDashboardOverview(
      courses: courses,
      studentEnrollments: studentEnrollments,
      schedules: schedules,
      sessions: sessions,
      assessments: assessments,
    );
  }

  Future<String> getCourseJoinCode(String courseId) async {
    final data = await _call('getCourseJoinCode', {'courseId': courseId});

    return data['joinCode'] as String;
  }

  Future<List<TeacherJoinRequest>> loadCourseJoinRequests(
    String courseId,
  ) async {
    final snapshot = await _database
        .collection('courseJoinRequests')
        .where('courseId', isEqualTo: courseId)
        .get();

    final requests = snapshot.docs
        .map(
          (document) =>
              TeacherJoinRequest.fromMap(document.id, document.data()),
        )
        .where((request) => request.status == 'pending')
        .toList();

    requests.sort((a, b) => a.institutionId.compareTo(b.institutionId));

    return requests;
  }

  Future<void> respondCourseJoinRequest({
    required String requestId,
    required bool approve,
  }) async {
    await _call('respondCourseJoinRequest', {
      'requestId': requestId,
      'response': approve ? 'approved' : 'rejected',
    });
  }

  Future<void> setAttendanceStatus({
    required String sessionId,
    required String studentId,
    required String status,
  }) async {
    await _call('setAttendanceStatus', {
      'sessionId': sessionId,
      'studentId': studentId,
      'status': status,
    });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final callable = _functions.httpsCallable(name);

      final result = await callable.call<Map<String, dynamic>>(data);

      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw TeacherAcademicServiceException(
        error.message ?? 'The operation failed.',
      );
    }
  }
}

class TeacherDashboardOverview {
  final List<TeacherCourse> courses;
  final int studentEnrollments;
  final List<TeacherScheduleEntry> schedules;
  final List<TeacherAttendanceSession> sessions;
  final List<TeacherAssessment> assessments;

  const TeacherDashboardOverview({
    required this.courses,
    required this.studentEnrollments,
    required this.schedules,
    required this.sessions,
    required this.assessments,
  });

  int get activeSessions =>
      sessions.where((session) => session.status == 'active').length;

  int get publishedAssessments => assessments
      .where((assessment) => assessment.status == 'published')
      .length;
}

class TeacherCourse {
  final String id;
  final String code;
  final String name;
  final String teacherId;
  final String teacherName;
  final String? department;
  final String? batch;
  final String? section;
  final String? semester;
  final String? room;
  final String? joinCode;
  final bool isActive;

  const TeacherCourse({
    required this.id,
    required this.code,
    required this.name,
    required this.teacherId,
    required this.teacherName,
    required this.department,
    required this.batch,
    required this.section,
    required this.semester,
    required this.room,
    required this.joinCode,
    required this.isActive,
  });

  TeacherCourse withJoinCode(String value) {
    return TeacherCourse(
      id: id,
      code: code,
      name: name,
      teacherId: teacherId,
      teacherName: teacherName,
      department: department,
      batch: batch,
      section: section,
      semester: semester,
      room: room,
      joinCode: value,
      isActive: isActive,
    );
  }

  factory TeacherCourse.fromMap(String id, Map<String, dynamic> data) {
    return TeacherCourse(
      id: id,
      code: data['code'] as String? ?? '',
      name: data['name'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
      department: _nullableText(data['department']),
      batch: _nullableText(data['batch']),
      section: _nullableText(data['section']),
      semester: _nullableText(data['semester']),
      room: _nullableText(data['room']),
      joinCode: _nullableText(data['joinCode']),
      isActive: data['isActive'] as bool? ?? false,
    );
  }
}

class EnrolledStudent {
  final String uid;
  final String institutionId;
  final String displayName;
  final String email;
  final bool isActive;

  const EnrolledStudent({
    required this.uid,
    required this.institutionId,
    required this.displayName,
    required this.email,
    required this.isActive,
  });

  factory EnrolledStudent.fromMap(String uid, Map<String, dynamic> data) {
    return EnrolledStudent(
      uid: uid,
      institutionId: data['institutionId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? true,
    );
  }
}

class TeacherJoinRequest {
  final String id;
  final String courseId;
  final String studentId;
  final String studentName;
  final String institutionId;
  final String email;
  final String status;

  const TeacherJoinRequest({
    required this.id,
    required this.courseId,
    required this.studentId,
    required this.studentName,
    required this.institutionId,
    required this.email,
    required this.status,
  });

  factory TeacherJoinRequest.fromMap(String id, Map<String, dynamic> data) {
    return TeacherJoinRequest(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      institutionId: data['institutionId'] as String? ?? '',
      email: data['email'] as String? ?? '',
      status: data['status'] as String? ?? '',
    );
  }
}

class TeacherScheduleEntry {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final int dayIndex;
  final String day;
  final String startTime;
  final String endTime;
  final String room;
  final String classType;
  final String status;

  const TeacherScheduleEntry({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.dayIndex,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.classType,
    required this.status,
  });

  factory TeacherScheduleEntry.fromMap(String id, Map<String, dynamic> data) {
    return TeacherScheduleEntry(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      dayIndex: (data['dayIndex'] as num?)?.toInt() ?? 0,
      day: data['day'] as String? ?? '',
      startTime: data['startTime'] as String? ?? '',
      endTime: data['endTime'] as String? ?? '',
      room: data['room'] as String? ?? '',
      classType: data['classType'] as String? ?? '',
      status: data['status'] as String? ?? 'scheduled',
    );
  }
}

class TeacherAttendanceSession {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String classType;
  final String status;
  final int durationMinutes;
  final bool requiresPasscode;
  final bool requiresGps;
  final bool allowLateEntry;
  final DateTime? startedAt;
  final DateTime? endsAt;

  const TeacherAttendanceSession({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.classType,
    required this.status,
    required this.durationMinutes,
    required this.requiresPasscode,
    required this.requiresGps,
    required this.allowLateEntry,
    required this.startedAt,
    required this.endsAt,
  });

  factory TeacherAttendanceSession.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return TeacherAttendanceSession(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      classType: data['classType'] as String? ?? '',
      status: data['status'] as String? ?? '',
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
      requiresPasscode: data['requiresPasscode'] as bool? ?? false,
      requiresGps: data['requiresGps'] as bool? ?? false,
      allowLateEntry: data['allowLateEntry'] as bool? ?? false,
      startedAt: _date(data['startedAt']),
      endsAt: _date(data['endsAt']),
    );
  }
}

class TeacherAttendanceRecord {
  final String id;
  final String studentId;
  final String institutionId;
  final String studentName;
  final String status;
  final DateTime? markedAt;

  const TeacherAttendanceRecord({
    required this.id,
    required this.studentId,
    required this.institutionId,
    required this.studentName,
    required this.status,
    required this.markedAt,
  });

  factory TeacherAttendanceRecord.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return TeacherAttendanceRecord(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      institutionId: data['institutionId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      status: data['status'] as String? ?? '',
      markedAt: _date(data['markedAt']),
    );
  }
}

class TeacherAssessment {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String name;
  final double maxScore;
  final String status;

  const TeacherAssessment({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.name,
    required this.maxScore,
    required this.status,
  });

  factory TeacherAssessment.fromMap(String id, Map<String, dynamic> data) {
    return TeacherAssessment(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      name: data['name'] as String? ?? '',
      maxScore: (data['maxScore'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? 'draft',
    );
  }
}

class TeacherMark {
  final String id;
  final String studentId;
  final double score;
  final double maxScore;
  final bool published;

  const TeacherMark({
    required this.id,
    required this.studentId,
    required this.score,
    required this.maxScore,
    required this.published,
  });

  factory TeacherMark.fromMap(String id, Map<String, dynamic> data) {
    return TeacherMark(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      score: (data['score'] as num?)?.toDouble() ?? 0,
      maxScore: (data['maxScore'] as num?)?.toDouble() ?? 0,
      published: data['published'] as bool? ?? false,
    );
  }
}

String? _nullableText(dynamic value) {
  if (value is! String) {
    return null;
  }

  final result = value.trim();

  return result.isEmpty ? null : result;
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  return null;
}

class TeacherAcademicServiceException implements Exception {
  final String message;

  const TeacherAcademicServiceException(this.message);

  @override
  String toString() => message;
}

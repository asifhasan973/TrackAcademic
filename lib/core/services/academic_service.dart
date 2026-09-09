import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AcademicService {
  const AcademicService();

  FirebaseFirestore get _database => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String get _currentUserId {
    final user = _auth.currentUser;

    if (user == null) {
      throw const AcademicServiceException('You are not signed in.');
    }

    return user.uid;
  }

  Future<List<String>> loadCurrentCourseIds() async {
    final uid = _currentUserId;

    final document = await _database.collection('users').doc(uid).get();

    final data = document.data();

    if (data == null) {
      throw const AcademicServiceException(
        'Your Trackademic profile could not be loaded.',
      );
    }

    final rawCourseIds = data['courseIds'];

    if (rawCourseIds is! List) {
      return const [];
    }

    final courseIds = rawCourseIds
        .whereType<String>()
        .map((courseId) => courseId.trim())
        .where((courseId) => courseId.isNotEmpty)
        .toSet()
        .toList();

    return courseIds;
  }

  Future<List<AcademicCourse>> loadCurrentCourses() async {
    final courseIds = await loadCurrentCourseIds();

    return _loadCourses(courseIds);
  }

  Future<List<StudentAttendanceSummary>> loadAttendanceSummaries() async {
    final courseIds = await loadCurrentCourseIds();

    return _loadAttendanceSummaries(courseIds);
  }

  Future<List<StudentMarkRecord>> loadPublishedMarks() async {
    final courseIds = await loadCurrentCourseIds();

    return _loadPublishedMarks(courseIds);
  }

  Future<List<ClassScheduleEntry>> loadCurrentSchedules() async {
    final courseIds = await loadCurrentCourseIds();

    return _loadSchedules(courseIds);
  }

  Future<List<AttendanceSessionInfo>> loadActiveAttendanceSessions() async {
    final courseIds = await loadCurrentCourseIds();

    return _loadActiveAttendanceSessions(courseIds);
  }

  Future<StudentAcademicOverview> loadStudentOverview() async {
    final courseIds = await loadCurrentCourseIds();

    if (courseIds.isEmpty) {
      return const StudentAcademicOverview(
        courses: [],
        attendance: [],
        marks: [],
        schedules: [],
        activeSessions: [],
      );
    }

    final results = await Future.wait<Object>([
      _loadCourses(courseIds),
      _loadAttendanceSummaries(courseIds),
      _loadPublishedMarks(courseIds),
      _loadSchedules(courseIds),
      _loadActiveAttendanceSessions(courseIds),
    ]);

    return StudentAcademicOverview(
      courses: results[0] as List<AcademicCourse>,
      attendance: results[1] as List<StudentAttendanceSummary>,
      marks: results[2] as List<StudentMarkRecord>,
      schedules: results[3] as List<ClassScheduleEntry>,
      activeSessions: results[4] as List<AttendanceSessionInfo>,
    );
  }

  Future<List<AcademicCourse>> _loadCourses(List<String> courseIds) async {
    if (courseIds.isEmpty) {
      return const [];
    }

    final documents = await Future.wait(
      courseIds.map(
        (courseId) => _database.collection('courses').doc(courseId).get(),
      ),
    );

    final courses = <AcademicCourse>[];

    for (final document in documents) {
      final data = document.data();

      if (!document.exists || data == null) {
        continue;
      }

      final course = AcademicCourse.fromMap(document.id, data);

      if (!course.isActive) {
        continue;
      }

      courses.add(course);
    }

    courses.sort((first, second) => first.code.compareTo(second.code));

    return courses;
  }

  Future<List<StudentAttendanceSummary>> _loadAttendanceSummaries(
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) {
      return const [];
    }

    final uid = _currentUserId;
    final summaries = <StudentAttendanceSummary>[];

    for (final courseId in courseIds) {
      final snapshot = await _database
          .collection('attendanceSummaries')
          .where('courseId', isEqualTo: courseId)
          .where('studentId', isEqualTo: uid)
          .get();

      for (final document in snapshot.docs) {
        summaries.add(
          StudentAttendanceSummary.fromMap(document.id, document.data()),
        );
      }
    }

    summaries.sort(
      (first, second) => first.courseCode.compareTo(second.courseCode),
    );

    return summaries;
  }

  Future<List<StudentMarkRecord>> _loadPublishedMarks(
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) {
      return const [];
    }

    final uid = _currentUserId;
    final marks = <StudentMarkRecord>[];

    for (final courseId in courseIds) {
      final snapshot = await _database
          .collection('marks')
          .where('courseId', isEqualTo: courseId)
          .where('studentId', isEqualTo: uid)
          .where('published', isEqualTo: true)
          .get();

      for (final document in snapshot.docs) {
        marks.add(StudentMarkRecord.fromMap(document.id, document.data()));
      }
    }

    marks.sort((first, second) {
      final courseComparison = first.courseCode.compareTo(second.courseCode);

      if (courseComparison != 0) {
        return courseComparison;
      }

      return first.assessmentName.compareTo(second.assessmentName);
    });

    return marks;
  }

  Future<List<ClassScheduleEntry>> _loadSchedules(
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) {
      return const [];
    }

    final schedules = <ClassScheduleEntry>[];

    for (final courseId in courseIds) {
      final snapshot = await _database
          .collection('schedules')
          .where('courseId', isEqualTo: courseId)
          .get();

      for (final document in snapshot.docs) {
        schedules.add(ClassScheduleEntry.fromMap(document.id, document.data()));
      }
    }

    schedules.sort((first, second) {
      final dayComparison = first.dayIndex.compareTo(second.dayIndex);

      if (dayComparison != 0) {
        return dayComparison;
      }

      return first.startTime.compareTo(second.startTime);
    });

    return schedules;
  }

  Future<List<AttendanceSessionInfo>> _loadActiveAttendanceSessions(
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) {
      return const [];
    }

    final sessions = <AttendanceSessionInfo>[];

    for (final courseId in courseIds) {
      final snapshot = await _database
          .collection('attendanceSessions')
          .where('courseId', isEqualTo: courseId)
          .get();

      for (final document in snapshot.docs) {
        final session = AttendanceSessionInfo.fromMap(
          document.id,
          document.data(),
        );

        if (session.status != 'active') {
          continue;
        }

        final endsAt = session.endsAt;

        if (endsAt != null && endsAt.isBefore(DateTime.now())) {
          continue;
        }

        sessions.add(session);
      }
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
}

class StudentAcademicOverview {
  final List<AcademicCourse> courses;
  final List<StudentAttendanceSummary> attendance;
  final List<StudentMarkRecord> marks;
  final List<ClassScheduleEntry> schedules;
  final List<AttendanceSessionInfo> activeSessions;

  const StudentAcademicOverview({
    required this.courses,
    required this.attendance,
    required this.marks,
    required this.schedules,
    required this.activeSessions,
  });

  int get totalClasses {
    return attendance.fold<int>(
      0,
      (totalValue, item) => totalValue + item.total,
    );
  }

  int get attendedClasses {
    return attendance.fold<int>(
      0,
      (totalValue, item) => totalValue + item.attended,
    );
  }

  double get overallAttendance {
    if (totalClasses == 0) {
      return 0;
    }

    return attendedClasses / totalClasses * 100;
  }

  double get averageAttendanceMarks {
    if (attendance.isEmpty) {
      return 0;
    }

    final total = attendance.fold<double>(
      0,
      (totalValue, item) => totalValue + item.attendanceMarks,
    );

    return total / attendance.length;
  }

  double get averageCtPercentage {
    final validMarks = marks.where((item) => item.maxScore > 0).toList();

    if (validMarks.isEmpty) {
      return 0;
    }

    final totalPercentage = validMarks.fold<double>(
      0,
      (totalValue, item) => totalValue + (item.score / item.maxScore * 100),
    );

    return totalPercentage / validMarks.length;
  }
}

class AcademicCourse {
  final String id;
  final String code;
  final String name;
  final String teacherId;
  final String teacherName;
  final String department;
  final String batch;
  final String section;
  final String semester;
  final String room;
  final bool isActive;

  const AcademicCourse({
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
    required this.isActive,
  });

  factory AcademicCourse.fromMap(String id, Map<String, dynamic> data) {
    return AcademicCourse(
      id: id,
      code: data['code'] as String? ?? '',
      name: data['name'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
      department: data['department'] as String? ?? '',
      batch: data['batch'] as String? ?? '',
      section: data['section'] as String? ?? '',
      semester: data['semester'] as String? ?? '',
      room: data['room'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? false,
    );
  }
}

class StudentAttendanceSummary {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String studentId;
  final int attended;
  final int total;
  final double percentage;
  final double attendanceMarks;

  const StudentAttendanceSummary({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.studentId,
    required this.attended,
    required this.total,
    required this.percentage,
    required this.attendanceMarks,
  });

  factory StudentAttendanceSummary.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    return StudentAttendanceSummary(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      attended: (data['attended'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      percentage: (data['percentage'] as num?)?.toDouble() ?? 0,
      attendanceMarks: (data['attendanceMarks'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StudentMarkRecord {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String assessmentId;
  final String assessmentName;
  final String studentId;
  final double score;
  final double maxScore;
  final bool published;

  const StudentMarkRecord({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.assessmentId,
    required this.assessmentName,
    required this.studentId,
    required this.score,
    required this.maxScore,
    required this.published,
  });

  factory StudentMarkRecord.fromMap(String id, Map<String, dynamic> data) {
    return StudentMarkRecord(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      assessmentId: data['assessmentId'] as String? ?? '',
      assessmentName: data['assessmentName'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      score: (data['score'] as num?)?.toDouble() ?? 0,
      maxScore: (data['maxScore'] as num?)?.toDouble() ?? 0,
      published: data['published'] as bool? ?? false,
    );
  }
}

class ClassScheduleEntry {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String teacherName;
  final int dayIndex;
  final String day;
  final String startTime;
  final String endTime;
  final String room;
  final String classType;
  final String status;

  const ClassScheduleEntry({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
    required this.dayIndex,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.classType,
    required this.status,
  });

  factory ClassScheduleEntry.fromMap(String id, Map<String, dynamic> data) {
    return ClassScheduleEntry(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
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

class AttendanceSessionInfo {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String teacherName;
  final String classType;
  final String status;
  final bool requiresPasscode;
  final bool requiresGps;
  final DateTime? startedAt;
  final DateTime? endsAt;

  const AttendanceSessionInfo({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
    required this.classType,
    required this.status,
    required this.requiresPasscode,
    required this.requiresGps,
    required this.startedAt,
    required this.endsAt,
  });

  factory AttendanceSessionInfo.fromMap(String id, Map<String, dynamic> data) {
    return AttendanceSessionInfo(
      id: id,
      courseId: data['courseId'] as String? ?? '',
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
      classType: data['classType'] as String? ?? '',
      status: data['status'] as String? ?? '',
      requiresPasscode: data['requiresPasscode'] as bool? ?? false,
      requiresGps: data['requiresGps'] as bool? ?? false,
      startedAt: _timestampToDate(data['startedAt']),
      endsAt: _timestampToDate(data['endsAt']),
    );
  }

  static DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}

class AcademicServiceException implements Exception {
  final String message;

  const AcademicServiceException(this.message);

  @override
  String toString() => message;
}

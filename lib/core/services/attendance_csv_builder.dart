import 'package:trackademic/core/services/teacher_academic_service.dart';

/// Pure Dart builder for attendance CSV exports.
///
/// Fully decoupled from platform file-saving and UI layers so it can be
/// thoroughly unit tested.
abstract final class AttendanceCsvBuilder {
  /// Escapes a field according to RFC 4180.
  ///
  /// If [value] contains commas, double quotes, or newlines, it is enclosed
  /// in double quotes, with internal quotes doubled (`""`).
  static String escapeField(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Sanitizes string components for safe filenames across filesystems.
  static String sanitizeFilenamePart(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return sanitized.isEmpty ? 'unnamed' : sanitized;
  }

  /// Generates a safe filename based on course code and session date.
  static String generateFilename({
    required String courseCode,
    required DateTime? date,
  }) {
    final cleanCode = sanitizeFilenamePart(courseCode.trim());
    final dateString = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : 'unknown_date';
    return 'attendance_${cleanCode}_$dateString.csv';
  }

  /// Formats the session date and time for CSV output.
  static String formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'N/A';
    }
    final y = dateTime.year;
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  /// Formats the marked time for an attendance record.
  static String formatMarkedTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'N/A';
    }
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  /// Builds a complete RFC 4180 CSV document string from session records.
  static String build({
    required String courseCode,
    required String courseName,
    required DateTime? sessionDate,
    required String classType,
    required List<EnrolledStudent> students,
    required Map<String, TeacherAttendanceRecord> records,
  }) {
    final buffer = StringBuffer();

    // Standard RFC 4180 Header
    buffer.write(
      'Course,Session Date,Class Type,Student Name,Institution ID,Status,Source,Marked Time\r\n',
    );

    final courseDisplay = courseName.isNotEmpty
        ? '$courseCode - $courseName'
        : courseCode;
    final formattedDate = formatDateTime(sessionDate);

    for (final student in students) {
      final record = records[student.uid];
      final status = record?.status ?? 'absent';
      final source = record?.source.isNotEmpty == true
          ? record!.source
          : 'finalization';
      final markedTime = formatMarkedTime(record?.markedAt);

      final row = [
        escapeField(courseDisplay),
        escapeField(formattedDate),
        escapeField(classType),
        escapeField(student.displayName),
        escapeField(student.institutionId),
        escapeField(status),
        escapeField(source),
        escapeField(markedTime),
      ].join(',');

      buffer.write('$row\r\n');
    }

    return buffer.toString();
  }

  /// Generates a safe filename for the full course register CSV.
  static String generateFullRegisterFilename({
    required String courseCode,
    DateTime? date,
  }) {
    final cleanCode = sanitizeFilenamePart(courseCode.trim());
    final effectiveDate = date ?? DateTime.now();
    final dateString =
        '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
    return 'attendance_${cleanCode}_full_register_$dateString.csv';
  }

  /// Builds a complete RFC 4180 CSV document representing the full course register.
  static String buildFullRegisterCsv({
    required String courseCode,
    required String courseName,
    required List<EnrolledStudent> students,
    required List<TeacherAttendanceSession> sessions,
    required Map<String, Map<String, String>> matrix,
  }) {
    final buffer = StringBuffer();

    final header = <String>[
      escapeField('Student Name'),
      escapeField('Roll/Institution ID'),
    ];

    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final dateStr = s.startedAt != null
          ? '${s.startedAt!.year}-${s.startedAt!.month.toString().padLeft(2, '0')}-${s.startedAt!.day.toString().padLeft(2, '0')}'
          : '';
      header.add(escapeField('Class ${i + 1} ($dateStr)'));
    }

    header.add(escapeField('Attended Classes'));
    header.add(escapeField('Total Classes'));
    header.add(escapeField('Attendance Percentage'));
    buffer.write('${header.join(',')}\r\n');

    final totalClasses = sessions.length;

    for (final student in students) {
      final studentStatuses = matrix[student.uid] ?? const {};
      var attended = 0;

      final row = <String>[
        escapeField(student.displayName),
        escapeField(student.institutionId),
      ];

      for (final session in sessions) {
        final rawStatus = (studentStatuses[session.id] ?? 'absent')
            .toLowerCase();
        String displayStatus;
        if (rawStatus == 'present') {
          displayStatus = 'Present';
          attended++;
        } else if (rawStatus == 'late') {
          displayStatus = 'Late';
          attended++;
        } else {
          displayStatus = 'Absent';
        }
        row.add(escapeField(displayStatus));
      }

      final percentage = totalClasses > 0
          ? (attended / totalClasses) * 100
          : 0.0;

      row.add(escapeField(attended.toString()));
      row.add(escapeField(totalClasses.toString()));
      row.add(escapeField('${percentage.toStringAsFixed(1)}%'));

      buffer.write('${row.join(',')}\r\n');
    }

    return buffer.toString();
  }
}

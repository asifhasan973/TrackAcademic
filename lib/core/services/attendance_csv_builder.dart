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
}

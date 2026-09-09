import 'package:trackademic/core/services/teacher_academic_service.dart';

/// Pure Dart builder for Student Academic Record CSV exports.
///
/// Complies with RFC 4180 and generates distinct sections for:
/// - Student & Course Information
/// - Attendance Summary
/// - Attendance History
/// - Assessment Marks & Overall Totals
///
/// Contains NO private passcodes, coordinates, device tokens, or internal auth metadata.
abstract final class StudentRecordCsvBuilder {
  /// Escapes a field according to RFC 4180.
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

  /// Generates a safe filename based on student institution ID and course code.
  static String generateFilename({
    required String studentInstitutionId,
    required String courseCode,
  }) {
    final cleanStudent = sanitizeFilenamePart(studentInstitutionId.trim());
    final cleanCourse = sanitizeFilenamePart(courseCode.trim());
    return 'student_record_${cleanStudent}_$cleanCourse.csv';
  }

  /// Formats a DateTime for CSV output.
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

  /// Builds a complete RFC 4180 CSV document for a student's academic record.
  static String build(TeacherStudentRecord record) {
    final buffer = StringBuffer();

    // 1. Student & Course Overview
    buffer.write('STUDENT ACADEMIC RECORD\r\n');
    buffer.write('Student Name,${escapeField(record.student.displayName)}\r\n');
    buffer.write(
      'Institution ID,${escapeField(record.student.institutionId)}\r\n',
    );
    buffer.write('Email,${escapeField(record.student.email)}\r\n');
    buffer.write(
      'Enrollment Status,${record.student.isActive ? 'Active' : 'Inactive (Historical)'}\r\n',
    );
    buffer.write('Course Code,${escapeField(record.courseCode)}\r\n');
    buffer.write('Course Name,${escapeField(record.courseName)}\r\n');
    buffer.write('\r\n');

    // 2. Attendance Summary
    buffer.write('ATTENDANCE SUMMARY\r\n');
    buffer.write(
      'Attended Classes,Total Classes,Percentage,Attendance Marks\r\n',
    );
    if (record.attendanceSummary != null) {
      final summary = record.attendanceSummary!;
      buffer.write(
        '${summary.attended},'
        '${summary.total},'
        '${summary.percentage.toStringAsFixed(1)}%,'
        '${summary.attendanceMarks.toStringAsFixed(2)}\r\n',
      );
    } else {
      buffer.write('0,0,0.0%,0.00\r\n');
    }
    buffer.write('\r\n');

    // 3. Attendance History
    buffer.write('ATTENDANCE HISTORY\r\n');
    buffer.write('Marked Time,Status,Source,Correction Reason\r\n');
    if (record.attendanceRecords.isEmpty) {
      buffer.write('No attendance sessions recorded for this student.\r\n');
    } else {
      for (final att in record.attendanceRecords) {
        final markedTime = formatDateTime(att.markedAt);
        final status = att.status;
        final source = att.source.isNotEmpty ? att.source : 'finalization';
        final reason = att.correctionReason ?? '';

        buffer.write(
          '${escapeField(markedTime)},'
          '${escapeField(status)},'
          '${escapeField(source)},'
          '${escapeField(reason)}\r\n',
        );
      }
    }
    buffer.write('\r\n');

    // 4. Assessment Marks
    buffer.write('ASSESSMENT MARKS\r\n');
    buffer.write(
      'Assessment Name,Type,Date,Score,Max Score,Percentage,Status,Correction Reason\r\n',
    );
    if (record.marks.isEmpty) {
      buffer.write('No marks recorded for this student.\r\n');
    } else {
      for (final mark in record.marks) {
        final percentage = mark.maxScore <= 0
            ? 0.0
            : (mark.score / mark.maxScore) * 100;
        final status = mark.published ? 'Published' : 'Draft';
        final reason = mark.correctionReason ?? '';

        buffer.write(
          '${escapeField(mark.assessmentName)},'
          '${escapeField(mark.assessmentType)},'
          '${escapeField(mark.assessmentDate)},'
          '${mark.score.toStringAsFixed(1)},'
          '${mark.maxScore.toStringAsFixed(1)},'
          '${percentage.toStringAsFixed(1)}%,'
          '${escapeField(status)},'
          '${escapeField(reason)}\r\n',
        );
      }
    }
    buffer.write('\r\n');

    // 5. Total Marks Overview
    buffer.write('MARKS TOTALS (PUBLISHED)\r\n');
    buffer.write('Total Earned,Total Possible,Overall Percentage\r\n');
    buffer.write(
      '${record.totalEarnedScore.toStringAsFixed(1)},'
      '${record.totalPossibleScore.toStringAsFixed(1)},'
      '${record.percentageScore.toStringAsFixed(1)}%\r\n',
    );

    return buffer.toString();
  }
}

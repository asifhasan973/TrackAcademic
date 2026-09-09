import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/attendance_csv_builder.dart';
import 'package:trackademic/core/services/file_saver/file_saver.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';

void main() {
  group('AttendanceCsvBuilder Unit Tests', () {
    test('escapes standard string without changes', () {
      expect(AttendanceCsvBuilder.escapeField('CSE101'), 'CSE101');
      expect(AttendanceCsvBuilder.escapeField('Theory'), 'Theory');
      expect(AttendanceCsvBuilder.escapeField('John Doe'), 'John Doe');
    });

    test('escapes values containing commas, quotes, and newlines', () {
      expect(AttendanceCsvBuilder.escapeField('Hasan, Asif'), '"Hasan, Asif"');
      expect(
        AttendanceCsvBuilder.escapeField('Student "Top" Performer'),
        '"Student ""Top"" Performer"',
      );
      expect(
        AttendanceCsvBuilder.escapeField('Line 1\nLine 2'),
        '"Line 1\nLine 2"',
      );
      expect(
        AttendanceCsvBuilder.escapeField('Line 1\r\nLine 2'),
        '"Line 1\r\nLine 2"',
      );
    });

    test('sanitizes filename components and produces safe filenames', () {
      final date = DateTime(2026, 9, 10, 14, 30);
      final filename = AttendanceCsvBuilder.generateFilename(
        courseCode: 'CSE 101/A:Lab',
        date: date,
      );

      expect(filename, 'attendance_CSE_101_A_Lab_2026-09-10.csv');
      expect(filename.contains('/'), isFalse);
      expect(filename.contains(':'), isFalse);
      expect(filename.contains(' '), isFalse);
    });

    test('handles null session date gracefully in filename and formatting', () {
      final filename = AttendanceCsvBuilder.generateFilename(
        courseCode: 'CSE101',
        date: null,
      );
      expect(filename, 'attendance_CSE101_unknown_date.csv');
      expect(AttendanceCsvBuilder.formatDateTime(null), 'N/A');
      expect(AttendanceCsvBuilder.formatMarkedTime(null), 'N/A');
    });

    test('builds compliant RFC 4180 CSV document', () {
      final sessionDate = DateTime(2026, 9, 10, 9, 0);
      final students = [
        const EnrolledStudent(
          uid: 's1',
          displayName: 'Alice, Wonder',
          institutionId: 'ID-001',
          email: 'alice@test.edu',
          isActive: true,
        ),
        const EnrolledStudent(
          uid: 's2',
          displayName: 'Bob "The Builder"',
          institutionId: 'ID-002',
          email: 'bob@test.edu',
          isActive: true,
        ),
        const EnrolledStudent(
          uid: 's3',
          displayName: 'Charlie',
          institutionId: 'ID-003',
          email: 'charlie@test.edu',
          isActive: true,
        ),
      ];

      final records = {
        's1': TeacherAttendanceRecord(
          id: 'rec_s1',
          studentId: 's1',
          institutionId: 'ID-001',
          studentName: 'Alice, Wonder',
          status: 'present',
          source: 'self',
          markedAt: DateTime(2026, 9, 10, 9, 5, 20),
        ),
        's2': TeacherAttendanceRecord(
          id: 'rec_s2',
          studentId: 's2',
          institutionId: 'ID-002',
          studentName: 'Bob "The Builder"',
          status: 'late',
          source: 'self',
          markedAt: DateTime(2026, 9, 10, 9, 16, 45),
        ),
        // s3 has no record (absent via finalization)
      };

      final csv = AttendanceCsvBuilder.build(
        courseCode: 'CSE 101',
        courseName: 'Algorithms',
        sessionDate: sessionDate,
        classType: 'Theory',
        students: students,
        records: records,
      );

      final lines = csv.split('\r\n');
      expect(
        lines[0],
        'Course,Session Date,Class Type,Student Name,Institution ID,Status,Source,Marked Time',
      );

      // Alice line: Name has comma, so quoted
      expect(lines[1], contains('"Alice, Wonder"'));
      expect(lines[1], contains('present'));
      expect(lines[1], contains('self'));
      expect(lines[1], contains('09:05:20'));

      // Bob line: Name has quotes, so doubled
      expect(lines[2], contains('"Bob ""The Builder"""'));
      expect(lines[2], contains('late'));
      expect(lines[2], contains('09:16:45'));

      // Charlie line: Default absent, finalization, N/A time
      expect(lines[3], contains('Charlie'));
      expect(lines[3], contains('absent'));
      expect(lines[3], contains('finalization'));
      expect(lines[3], contains('N/A'));
    });

    test('FileSaver interface can be instantiated via platform factory', () {
      final saver = FileSaver();
      expect(saver, isNotNull);
    });

    test('pure CSV generation is decoupled from platform saving', () async {
      // Custom test saver demonstrating separation of concerns
      final memorySaved = <String, String>{};
      final testSaver = _MockMemorySaver(memorySaved);

      final content = AttendanceCsvBuilder.build(
        courseCode: 'TEST101',
        courseName: 'Test Course',
        sessionDate: DateTime(2026, 9, 10),
        classType: 'Lab',
        students: const [
          EnrolledStudent(
            uid: 'stu1',
            displayName: 'Test Student',
            institutionId: 'ID-001',
            email: 'test@student.edu',
            isActive: true,
          ),
        ],
        records: const {},
      );

      final filename = AttendanceCsvBuilder.generateFilename(
        courseCode: 'TEST101',
        date: DateTime(2026, 9, 10),
      );

      final result = await testSaver.saveFile(
        filename: filename,
        content: content,
        mimeType: 'text/csv',
      );

      expect(result, filename);
      expect(memorySaved[filename], content);
      expect(memorySaved[filename], contains('TEST101'));
      expect(memorySaved[filename], contains('ID-001'));
    });
  });
}

class _MockMemorySaver implements FileSaver {
  final Map<String, String> storage;

  _MockMemorySaver(this.storage);

  @override
  Future<String> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  }) async {
    storage[filename] = content;
    return filename;
  }
}

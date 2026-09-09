import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/student_record_csv_builder.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';

void main() {
  group('StudentRecordCsvBuilder Unit Tests', () {
    test('escapes standard strings and strings with special characters', () {
      expect(StudentRecordCsvBuilder.escapeField('CSE101'), 'CSE101');
      expect(
        StudentRecordCsvBuilder.escapeField('Hasan, Asif'),
        '"Hasan, Asif"',
      );
      expect(
        StudentRecordCsvBuilder.escapeField('Grade "A+" Special'),
        '"Grade ""A+"" Special"',
      );
      expect(
        StudentRecordCsvBuilder.escapeField('Line1\nLine2'),
        '"Line1\nLine2"',
      );
      expect(
        StudentRecordCsvBuilder.escapeField('Line1\r\nLine2'),
        '"Line1\r\nLine2"',
      );
    });

    test('generates safe filename with sanitized characters', () {
      final filename = StudentRecordCsvBuilder.generateFilename(
        studentInstitutionId: 'STU/2026:001',
        courseCode: 'CSE 101/A',
      );
      expect(filename, 'student_record_STU_2026_001_CSE_101_A.csv');
      expect(filename.contains('/'), isFalse);
      expect(filename.contains(':'), isFalse);
      expect(filename.contains(' '), isFalse);
    });

    test('formats dates correctly and handles null safely', () {
      expect(StudentRecordCsvBuilder.formatDateTime(null), 'N/A');
      final dt = DateTime(2026, 9, 15, 14, 30);
      expect(StudentRecordCsvBuilder.formatDateTime(dt), '2026-09-15 14:30');
    });

    test('builds full RFC 4180 CSV document with all sections', () {
      const student = EnrolledStudent(
        uid: 'student_123',
        institutionId: 'ID-456',
        displayName: 'John, "Doc" Doe',
        email: 'john@uni.edu',
        isActive: true,
      );

      const summary = TeacherAttendanceSummary(
        id: 'CSE101_student_123',
        courseId: 'course_cse101',
        courseCode: 'CSE101',
        courseName: 'Intro to Programming',
        studentId: 'student_123',
        attended: 12,
        total: 15,
        percentage: 80.0,
        attendanceMarks: 8.0,
      );

      final attendanceRecords = [
        TeacherAttendanceRecord(
          id: 'rec_1',
          studentId: 'student_123',
          institutionId: 'ID-456',
          studentName: 'John Doe',
          status: 'present',
          source: 'session',
          correctionReason: null,
          markedAt: DateTime(2026, 9, 1, 9, 5),
        ),
        TeacherAttendanceRecord(
          id: 'rec_2',
          studentId: 'student_123',
          institutionId: 'ID-456',
          studentName: 'John Doe',
          status: 'present',
          source: 'correction',
          correctionReason: 'Medical excuse provided',
          markedAt: DateTime(2026, 9, 3, 9, 0),
        ),
      ];

      final marks = [
        const TeacherStudentMark(
          id: 'mark_1',
          assessmentId: 'asst_1',
          assessmentName: 'Quiz 1',
          assessmentType: 'Quiz',
          assessmentDate: '2026-09-05',
          courseId: 'course_cse101',
          studentId: 'student_123',
          score: 18.0,
          maxScore: 20.0,
          published: true,
          previousScore: 15.0,
          correctionReason: 'Regraded problem 2',
        ),
        const TeacherStudentMark(
          id: 'mark_2',
          assessmentId: 'asst_2',
          assessmentName: 'Midterm Exam',
          assessmentType: 'Midterm',
          assessmentDate: '2026-09-12',
          courseId: 'course_cse101',
          studentId: 'student_123',
          score: 45.0,
          maxScore: 50.0,
          published: true,
        ),
      ];

      final record = TeacherStudentRecord(
        student: student,
        courseId: 'course_cse101',
        courseCode: 'CSE101',
        courseName: 'Intro to Programming',
        attendanceSummary: summary,
        attendanceRecords: attendanceRecords,
        marks: marks,
      );

      final csv = StudentRecordCsvBuilder.build(record);

      // Verify sections exist
      expect(csv.contains('STUDENT ACADEMIC RECORD'), isTrue);
      expect(csv.contains('ATTENDANCE SUMMARY'), isTrue);
      expect(csv.contains('ATTENDANCE HISTORY'), isTrue);
      expect(csv.contains('ASSESSMENT MARKS'), isTrue);
      expect(csv.contains('MARKS TOTALS (PUBLISHED)'), isTrue);

      // Verify escaped student name
      expect(csv.contains('"John, ""Doc"" Doe"'), isTrue);
      expect(csv.contains('ID-456'), isTrue);
      expect(csv.contains('Active'), isTrue);

      // Verify attendance summary
      expect(csv.contains('12,15,80.0%,8.00'), isTrue);

      // Verify attendance records
      expect(csv.contains('present,session,'), isTrue);
      expect(
        csv.contains('present,correction,Medical excuse provided'),
        isTrue,
      );

      // Verify marks
      expect(
        csv.contains(
          'Quiz 1,Quiz,2026-09-05,18.0,20.0,90.0%,Published,Regraded problem 2',
        ),
        isTrue,
      );
      expect(
        csv.contains(
          'Midterm Exam,Midterm,2026-09-12,45.0,50.0,90.0%,Published,',
        ),
        isTrue,
      );

      // Verify totals
      expect(csv.contains('63.0,70.0,90.0%'), isTrue);

      // Verify no sensitive tokens/coordinates/passcodes exist in the output
      expect(csv.toLowerCase().contains('passcode'), isFalse);
      expect(csv.toLowerCase().contains('latitude'), isFalse);
      expect(csv.toLowerCase().contains('longitude'), isFalse);
      expect(csv.toLowerCase().contains('devicetoken'), isFalse);
    });

    test('handles historical inactive enrollment correctly in CSV', () {
      const student = EnrolledStudent(
        uid: 'student_past',
        institutionId: 'ID-PAST',
        displayName: 'Past Student',
        email: 'past@uni.edu',
        isActive: false,
      );

      final record = TeacherStudentRecord(
        student: student,
        courseId: 'course_cse101',
        courseCode: 'CSE101',
        courseName: 'Intro to Programming',
        attendanceSummary: null,
        attendanceRecords: const [],
        marks: const [],
      );

      final csv = StudentRecordCsvBuilder.build(record);

      expect(csv.contains('Inactive (Historical)'), isTrue);
      expect(csv.contains('No attendance sessions recorded'), isTrue);
      expect(csv.contains('No marks recorded'), isTrue);
      expect(csv.contains('0.0,0.0,0.0%'), isTrue);
    });
  });
}

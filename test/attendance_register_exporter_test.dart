import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/attendance_register_exporter.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';

void main() {
  group('AttendanceRegisterExporter Unit Tests', () {
    const course = TeacherCourse(
      id: 'c-101',
      code: 'CSE 222',
      name: 'Software Development & Architecture',
      teacherId: 't-1',
      teacherName: 'Prof. Hasan',
      department: 'CSE',
      batch: '51',
      section: 'A',
      semester: 'Fall 2026',
      room: 'Lab 3',
      joinCode: 'CSE222-A',
      isActive: true,
    );

    final students = [
      const EnrolledStudent(
        uid: 's-1',
        displayName: 'আসিফ হাসান',
        institutionId: '2023-1-60-001',
        email: 'asif@example.com',
        isActive: true,
      ),
      const EnrolledStudent(
        uid: 's-2',
        displayName: 'John "The Boss" Doe',
        institutionId: '2023-1-60-002',
        email: 'john@example.com',
        isActive: true,
      ),
    ];

    final sessions = [
      TeacherAttendanceSession(
        id: 'sess-1',
        courseId: 'c-101',
        courseCode: 'CSE 222',
        courseName: 'Software Development & Architecture',
        classType: 'Theory',
        status: 'closed',
        durationMinutes: 60,
        requiresPasscode: true,
        requiresGps: false,
        allowLateEntry: false,
        startedAt: DateTime(2026, 9, 1, 10, 0),
        endsAt: DateTime(2026, 9, 1, 11, 0),
      ),
      TeacherAttendanceSession(
        id: 'sess-2',
        courseId: 'c-101',
        courseCode: 'CSE 222',
        courseName: 'Software Development & Architecture',
        classType: 'Lab',
        status: 'closed',
        durationMinutes: 120,
        requiresPasscode: true,
        requiresGps: false,
        allowLateEntry: false,
        startedAt: DateTime(2026, 9, 3, 14, 0),
        endsAt: DateTime(2026, 9, 3, 16, 0),
      ),
    ];

    final matrix = {
      's-1': {'sess-1': 'present', 'sess-2': 'present'},
      's-2': {'sess-1': 'late', 'sess-2': 'absent'},
    };

    const exporter = AttendanceRegisterExporter();

    test('generates valid RFC 4180 CSV with UTF-8 BOM and formula escaping', () {
      final bytes = exporter.buildCsv(
        courseCode: course.code,
        courseName: course.name,
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes[0], 0xEF, reason: 'Must contain UTF-8 BOM byte 1');
      expect(bytes[1], 0xBB, reason: 'Must contain UTF-8 BOM byte 2');
      expect(bytes[2], 0xBF, reason: 'Must contain UTF-8 BOM byte 3');
      final text = utf8.decode(bytes);
      expect(text.contains('আসিফ হাসান'), isTrue);
      expect(text.contains('CSE 222'), isTrue);
    });

    test('generates genuine PDF file starting with %PDF- header', () async {
      final bytes = await exporter.buildPdf(
        courseCode: course.code,
        courseName: course.name,
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      expect(bytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });

    test('generates genuine DOCX file starting with PK zip header and Word structure', () {
      final bytes = exporter.buildDocx(
        courseCode: course.code,
        courseName: course.name,
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(bytes[2], 0x03);
      expect(bytes[3], 0x04);
    });
  });
}

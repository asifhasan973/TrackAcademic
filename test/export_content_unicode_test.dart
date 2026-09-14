import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/core/services/attendance_register_exporter.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttendanceRegisterExporter Content & Unicode Tests', () {
    const exporter = AttendanceRegisterExporter();

    final students = [
      const EnrolledStudent(
        uid: 'stud_1',
        displayName: 'মোঃ আসিফ হাসান', // Bengali name with complex script
        email: 'asif@example.com',
        institutionId: '2021-001',
        isActive: true,
      ),
      const EnrolledStudent(
        uid: 'stud_2',
        displayName: 'তানভীর আহমেদ', // Bengali name with vowel diacritics
        email: 'tanvir@example.com',
        institutionId: '2021-002',
        isActive: true,
      ),
    ];

    // Create 15 sessions to test wide register chunking (chunk size = 10)
    final sessions = List.generate(
      15,
      (i) => TeacherAttendanceSession(
        id: 'sess_$i',
        courseId: 'cse101',
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        classType: 'Theory',
        status: 'completed',
        durationMinutes: 60,
        requiresPasscode: false,
        requiresGps: false,
        allowLateEntry: false,
        startedAt: DateTime(2026, 9, 1 + i, 10, 0),
        endsAt: DateTime(2026, 9, 1 + i, 11, 0),
      ),
    );

    final matrix = {
      'stud_1': {
        for (var i = 0; i < 15; i++) 'sess_$i': i % 2 == 0 ? 'present' : 'absent',
      },
      'stud_2': {
        for (var i = 0; i < 15; i++) 'sess_$i': 'present',
      },
    };

    test('CSV export includes UTF-8 BOM, Bengali names, and formula protection', () {
      final bytes = exporter.buildCsv(
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      // Verify genuine UTF-8 BOM bytes (0xEF, 0xBB, 0xBF)
      expect(bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF, isTrue);
      final text = utf8.decode(bytes);
      expect(text.contains('মোঃ আসিফ হাসান'), isTrue); // Bengali preserved
      expect(text.contains('তানভীর আহমেদ'), isTrue);
    });

    test('DOCX export includes complex script fonts, dates in headers, and chunked tables', () {
      final bytes = exporter.buildDocx(
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      expect(bytes.isNotEmpty, isTrue);

      // Verify it's a valid ZIP archive containing Word document structure
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXmlFile = archive.findFile('word/document.xml');
      expect(docXmlFile, isNotNull);

      final xmlContent = utf8.decode(docXmlFile!.content as List<int>);

      // Check Unicode complex script font declaration
      expect(xmlContent.contains('Noto Sans Bengali'), isTrue);

      // Check Bengali names are preserved in document XML
      expect(xmlContent.contains('মোঃ আসিফ হাসান'), isTrue);
      expect(xmlContent.contains('তানভীর আহমেদ'), isTrue);

      // Check class dates are present in headers: C1 (01/09)
      expect(xmlContent.contains('C1 (01/09)'), isTrue);

      // Check chunking into multiple sections (Classes 1 - 10 and Classes 11 - 15)
      expect(xmlContent.contains('Classes 1 - 10'), isTrue);
      expect(xmlContent.contains('Classes 11 - 15'), isTrue);
    });

    test('PDF export handles Unicode/Bengali and chunking without error', () async {
      final bytes = await exporter.buildPdf(
        courseCode: 'CSE 101',
        courseName: 'Structured Programming',
        students: students,
        sessions: sessions,
        matrix: matrix,
      );

      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(1000));
      // PDF header check
      final header = String.fromCharCodes(bytes.sublist(0, 5));
      expect(header, '%PDF-');
    });

    test('Legacy .doc throws UnsupportedError with Pending Decision notice', () {
      expect(
        () => exporter.exportRegister(
          format: ExportFormat.doc,
          courseCode: 'CSE 101',
          courseName: 'Test',
          students: students,
          sessions: sessions,
          matrix: matrix,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

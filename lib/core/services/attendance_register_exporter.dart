import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:trackademic/core/services/attendance_csv_builder.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';

enum ExportFormat {
  csv,
  pdf,
  docx,
  doc,
}

class ExportResult {
  final String filename;
  final Uint8List bytes;
  final String mimeType;
  final ExportFormat format;

  const ExportResult({
    required this.filename,
    required this.bytes,
    required this.mimeType,
    required this.format,
  });
}

class AttendanceRegisterExporter {
  const AttendanceRegisterExporter();

  /// Maximum number of attendance columns per table section to ensure optimal readability on A4
  static const int maxColumnsPerChunk = 10;

  /// Generates safe collision-resistant filename
  static String generateFilename({
    required String courseCode,
    required ExportFormat format,
    DateTime? date,
  }) {
    final cleanCode = AttendanceCsvBuilder.sanitizeFilenamePart(courseCode.trim());
    final effectiveDate = date ?? DateTime.now();
    final dateString =
        '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
    final ext = switch (format) {
      ExportFormat.csv => 'csv',
      ExportFormat.pdf => 'pdf',
      ExportFormat.docx => 'docx',
      ExportFormat.doc => 'doc',
    };
    return 'attendance_${cleanCode}_register_$dateString.$ext';
  }

  static String _formatSessionDate(TeacherAttendanceSession session) {
    final date = session.startedAt ?? session.endsAt;
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  /// Builds RFC 4180 CSV register with Bengali/Unicode UTF-8 BOM
  Uint8List buildCsv({
    required String courseCode,
    required String courseName,
    required List<EnrolledStudent> students,
    required List<TeacherAttendanceSession> sessions,
    required Map<String, Map<String, String>> matrix,
  }) {
    final content = AttendanceCsvBuilder.buildFullRegisterCsv(
      courseCode: courseCode,
      courseName: courseName,
      students: students,
      sessions: sessions,
      matrix: matrix,
    );
    return Uint8List.fromList(utf8.encode(content));
  }

  /// Builds Genuine Landscape PDF with Unicode font embedding and column chunking
  Future<Uint8List> buildPdf({
    required String courseCode,
    required String courseName,
    required List<EnrolledStudent> students,
    required List<TeacherAttendanceSession> sessions,
    required Map<String, Map<String, String>> matrix,
  }) async {
    // Load Unicode fonts with Bengali fallback support
    pw.Font? ttfFont;
    pw.Font? bengaliFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      ttfFont = pw.Font.ttf(fontData);
    } catch (_) {}

    try {
      final bengaliData =
          await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      bengaliFont = pw.Font.ttf(bengaliData);
    } catch (_) {}

    final theme = (ttfFont != null)
        ? pw.ThemeData.withFont(
            base: ttfFont,
            bold: ttfFont,
            fontFallback: bengaliFont != null ? [bengaliFont] : const [],
          )
        : pw.ThemeData.base();

    final doc = pw.Document(theme: theme);
    final totalClasses = sessions.length;
    final exportDateStr = AttendanceCsvBuilder.formatDateTime(DateTime.now());

    // Divide sessions into chunks so wide registers remain clear and readable
    final chunks = <List<TeacherAttendanceSession>>[];
    if (sessions.isEmpty) {
      chunks.add([]);
    } else {
      for (var i = 0; i < sessions.length; i += maxColumnsPerChunk) {
        chunks.add(
          sessions.sublist(
            i,
            min(i + maxColumnsPerChunk, sessions.length),
          ),
        );
      }
    }

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];
      final isLastChunk = (chunkIndex == chunks.length - 1);
      final startClassNum = chunkIndex * maxColumnsPerChunk + 1;
      final endClassNum = chunkIndex * maxColumnsPerChunk + chunk.length;

      // Table Headers
      final headers = <String>[
        'Student Name',
        'Roll / ID',
      ];

      for (var i = 0; i < chunk.length; i++) {
        final session = chunk[i];
        final classNumber = startClassNum + i;
        final dateStr = _formatSessionDate(session);
        headers.add(dateStr.isNotEmpty ? 'C$classNumber\n$dateStr' : 'C$classNumber');
      }

      if (isLastChunk) {
        headers.addAll(['Attended', 'Total', '%']);
      }

      // Table Rows
      final tableData = <List<String>>[];
      for (final student in students) {
        final studentStatuses = matrix[student.uid] ?? const {};
        final row = <String>[
          student.displayName.isNotEmpty ? student.displayName : 'Student',
          student.institutionId,
        ];

        for (final session in chunk) {
          final rawStatus = (studentStatuses[session.id] ?? 'absent').toLowerCase();
          if (rawStatus == 'present') {
            row.add('P');
          } else if (rawStatus == 'late') {
            row.add('L');
          } else {
            row.add('A');
          }
        }

        if (isLastChunk) {
          var totalAttended = 0;
          for (final s in sessions) {
            final st = (studentStatuses[s.id] ?? 'absent').toLowerCase();
            if (st == 'present' || st == 'late') totalAttended++;
          }
          final percentage = totalClasses > 0 ? (totalAttended / totalClasses) * 100 : 0.0;
          row.addAll(['$totalAttended', '$totalClasses', '${percentage.toStringAsFixed(1)}%']);
        }

        tableData.add(row);
      }

      final chunkSubtitle = totalClasses > 0
          ? 'Course: $courseCode - $courseName  |  Classes $startClassNum - $endClassNum of $totalClasses  |  Generated: $exportDateStr'
          : 'Course: $courseCode - $courseName  |  No sessions recorded  |  Generated: $exportDateStr';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TrackAcademic - Attendance Register',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Text(
                        'Section ${chunkIndex + 1}/${chunks.length}  •  Page ${context.pageNumber} of ${context.pagesCount}',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    chunkSubtitle,
                    style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800),
                  ),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: tableData,
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
                cellStyle: const pw.TextStyle(fontSize: 7),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  for (var col = 2; col < headers.length; col++)
                    col: pw.Alignment.center,
                },
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
              ),
            ];
          },
        ),
      );
    }

    return doc.save();
  }

  /// Builds Genuine OpenXML Word Document (.docx) with repeated headers, dates, and column chunking
  Uint8List buildDocx({
    required String courseCode,
    required String courseName,
    required List<EnrolledStudent> students,
    required List<TeacherAttendanceSession> sessions,
    required Map<String, Map<String, String>> matrix,
  }) {
    final archive = Archive();
    final totalClasses = sessions.length;
    final exportDateStr = AttendanceCsvBuilder.formatDateTime(DateTime.now());

    String xmlEscape(String text) {
      return text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
    }

    // [Content_Types].xml
    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';
    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)));

    // _rels/.rels
    const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';
    archive.addFile(ArchiveFile('_rels/.rels', rootRels.length, utf8.encode(rootRels)));

    // word/_rels/document.xml.rels
    const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels', docRels.length, utf8.encode(docRels)));

    // docProps/core.xml
    final coreXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
  <dc:title>Attendance Register - ${xmlEscape(courseCode)}</dc:title>
  <dc:creator>TrackAcademic</dc:creator>
  <cp:lastModifiedBy>TrackAcademic</cp:lastModifiedBy>
  <dcterms:created>${DateTime.now().toUtc().toIso8601String()}</dcterms:created>
</cp:coreProperties>''';
    archive.addFile(ArchiveFile('docProps/core.xml', coreXml.length, utf8.encode(coreXml)));

    // docProps/app.xml
    const appXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>TrackAcademic</Application>
</Properties>''';
    archive.addFile(ArchiveFile('docProps/app.xml', appXml.length, utf8.encode(appXml)));

    // word/document.xml with Unicode Bengali fonts & chunked tables
    final docBuffer = StringBuffer();
    docBuffer.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1E3A8A"/></w:rPr>
        <w:t>TrackAcademic - Attendance Register</w:t>
      </w:r>
    </w:p>
    <w:p>
      <w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr><w:sz w:val="20"/><w:color w:val="475569"/></w:rPr>
        <w:t>Course: ${xmlEscape(courseCode)} - ${xmlEscape(courseName)} | Generated: $exportDateStr | Total Classes: $totalClasses</w:t>
      </w:r>
    </w:p>
''');

    final chunks = <List<TeacherAttendanceSession>>[];
    if (sessions.isEmpty) {
      chunks.add([]);
    } else {
      for (var i = 0; i < sessions.length; i += maxColumnsPerChunk) {
        chunks.add(sessions.sublist(i, min(i + maxColumnsPerChunk, sessions.length)));
      }
    }

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];
      final isLastChunk = (chunkIndex == chunks.length - 1);
      final startClassNum = chunkIndex * maxColumnsPerChunk + 1;
      final endClassNum = chunkIndex * maxColumnsPerChunk + chunk.length;

      docBuffer.write('''    <w:p>
      <w:pPr><w:spacing w:before="240" w:after="80"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="22"/><w:color w:val="1E3A8A"/></w:rPr>
        <w:t>${totalClasses > 0 ? 'Section ${chunkIndex + 1}: Classes $startClassNum - $endClassNum' : 'Classes'}</w:t>
      </w:r>
    </w:p>
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="0" w:type="auto"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:left w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:right w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>
        </w:tblBorders>
      </w:tblPr>
''');

      // Header Row
      docBuffer.write('''      <w:tr>
        <w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>
        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Noto Sans Bengali"/><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Student Name</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Noto Sans Bengali"/><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Roll / ID</w:t></w:r></w:p></w:tc>
''');

      for (var i = 0; i < chunk.length; i++) {
        final session = chunk[i];
        final classNum = startClassNum + i;
        final dateStr = _formatSessionDate(session);
        final label = dateStr.isNotEmpty ? 'C$classNum ($dateStr)' : 'C$classNum';
        docBuffer.write(
          '        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="16"/></w:rPr><w:t>${xmlEscape(label)}</w:t></w:r></w:p></w:tc>\n',
        );
      }

      if (isLastChunk) {
        docBuffer.write('''        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Attended</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>Total</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="1E3A8A"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/><w:sz w:val="18"/></w:rPr><w:t>%</w:t></w:r></w:p></w:tc>
''');
      }
      docBuffer.write('      </w:tr>\n');

      // Student Data Rows
      for (final student in students) {
        final studentStatuses = matrix[student.uid] ?? const {};
        docBuffer.write('''      <w:tr>
        <w:trPr><w:cantSplit/></w:trPr>
        <w:tc><w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Noto Sans Bengali"/><w:sz w:val="18"/></w:rPr><w:t>${xmlEscape(student.displayName.isNotEmpty ? student.displayName : 'Student')}</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Noto Sans Bengali"/><w:sz w:val="18"/></w:rPr><w:t>${xmlEscape(student.institutionId)}</w:t></w:r></w:p></w:tc>
''');

        for (final session in chunk) {
          final rawStatus = (studentStatuses[session.id] ?? 'absent').toLowerCase();
          final code = switch (rawStatus) {
            'present' => 'P',
            'late' => 'L',
            _ => 'A',
          };
          docBuffer.write(
            '        <w:tc><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>$code</w:t></w:r></w:p></w:tc>\n',
          );
        }

        if (isLastChunk) {
          var totalAttended = 0;
          for (final s in sessions) {
            final st = (studentStatuses[s.id] ?? 'absent').toLowerCase();
            if (st == 'present' || st == 'late') totalAttended++;
          }
          final percentage = totalClasses > 0 ? (totalAttended / totalClasses) * 100 : 0.0;
          docBuffer.write('''        <w:tc><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>$totalAttended</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>$totalClasses</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>${percentage.toStringAsFixed(1)}%</w:t></w:r></w:p></w:tc>
''');
        }
        docBuffer.write('      </w:tr>\n');
      }

      docBuffer.write('    </w:tbl>\n');
    }

    // Page Setup: Landscape A4 (16838 x 11906 dxa)
    docBuffer.write('''    <w:sectPr>
      <w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>
      <w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="720" w:footer="720"/>
    </w:sectPr>
  </w:body>
</w:document>''');

    archive.addFile(
      ArchiveFile(
        'word/document.xml',
        utf8.encode(docBuffer.toString()).length,
        utf8.encode(docBuffer.toString()),
      ),
    );

    final zipEncoder = ZipEncoder();
    final encodedZip = zipEncoder.encode(archive);
    return Uint8List.fromList(encodedZip);
  }

  /// Builds the requested format
  Future<ExportResult> exportRegister({
    required ExportFormat format,
    required String courseCode,
    required String courseName,
    required List<EnrolledStudent> students,
    required List<TeacherAttendanceSession> sessions,
    required Map<String, Map<String, String>> matrix,
  }) async {
    final filename = generateFilename(courseCode: courseCode, format: format);
    switch (format) {
      case ExportFormat.csv:
        final bytes = buildCsv(
          courseCode: courseCode,
          courseName: courseName,
          students: students,
          sessions: sessions,
          matrix: matrix,
        );
        return ExportResult(
          filename: filename,
          bytes: bytes,
          mimeType: 'text/csv',
          format: format,
        );
      case ExportFormat.pdf:
        final bytes = await buildPdf(
          courseCode: courseCode,
          courseName: courseName,
          students: students,
          sessions: sessions,
          matrix: matrix,
        );
        return ExportResult(
          filename: filename,
          bytes: bytes,
          mimeType: 'application/pdf',
          format: format,
        );
      case ExportFormat.docx:
        final bytes = buildDocx(
          courseCode: courseCode,
          courseName: courseName,
          students: students,
          sessions: sessions,
          matrix: matrix,
        );
        return ExportResult(
          filename: filename,
          bytes: bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          format: format,
        );
      case ExportFormat.doc:
        throw UnsupportedError(
          'Legacy Word 97-2003 (.doc) binary format is pending format decision. Please choose DOCX for Microsoft Word.',
        );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:trackademic/core/services/attendance_register_exporter.dart';
import 'package:trackademic/core/services/platform_storage_service.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/core/widgets/inline_error_banner.dart';

/// Shows the Export Register bottom sheet modal.
Future<void> showExportRegisterSheet({
  required BuildContext context,
  required String courseCode,
  required String courseName,
  required List<EnrolledStudent> students,
  required List<TeacherAttendanceSession> sessions,
  required Map<String, Map<String, String>> matrix,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ExportRegisterSheetContent(
      courseCode: courseCode,
      courseName: courseName,
      students: students,
      sessions: sessions,
      matrix: matrix,
    ),
  );
}

class _ExportRegisterSheetContent extends StatefulWidget {
  final String courseCode;
  final String courseName;
  final List<EnrolledStudent> students;
  final List<TeacherAttendanceSession> sessions;
  final Map<String, Map<String, String>> matrix;

  const _ExportRegisterSheetContent({
    required this.courseCode,
    required this.courseName,
    required this.students,
    required this.sessions,
    required this.matrix,
  });

  @override
  State<_ExportRegisterSheetContent> createState() =>
      _ExportRegisterSheetContentState();
}

class _ExportRegisterSheetContentState
    extends State<_ExportRegisterSheetContent> {
  static const _exporter = AttendanceRegisterExporter();
  static const _storage = PlatformStorageService();

  bool _isExporting = false;
  String? _exportingFormatName;
  SavedFileResult? _lastSavedResult;
  String? _errorMessage;

  Future<void> _performExport(ExportFormat format) async {
    if (format == ExportFormat.doc) {
      setState(() {
        _errorMessage =
            'Legacy Word 97-2003 (.doc) binary format cannot be generated locally without external paid conversion services. Please choose modern DOCX for Microsoft Word compatibility.';
      });
      return;
    }

    setState(() {
      _isExporting = true;
      _exportingFormatName = format.name.toUpperCase();
      _errorMessage = null;
      _lastSavedResult = null;
    });

    try {
      final result = await _exporter.exportRegister(
        format: format,
        courseCode: widget.courseCode,
        courseName: widget.courseName,
        students: widget.students,
        sessions: widget.sessions,
        matrix: widget.matrix,
      );

      final saved = await _storage.saveToDownloads(
        filename: result.filename,
        bytes: result.bytes,
        mimeType: result.mimeType,
      );

      if (!mounted) return;
      setState(() {
        _lastSavedResult = saved;
        _isExporting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Export failed: $e';
        _isExporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.small),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: const Icon(
                      Icons.file_download_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export Attendance Register',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${widget.courseCode} · ${widget.students.length} students · ${widget.sessions.length} sessions',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_errorMessage != null)
                InlineErrorBanner(
                  message: _errorMessage!,
                  onDismiss: () => setState(() => _errorMessage = null),
                ),

              if (_lastSavedResult != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Saved to ${_lastSavedResult!.displayPath}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onPressed: () => _storage.openFile(
                                uri: _lastSavedResult!.uri,
                                mimeType: _lastSavedResult!.mimeType,
                              ),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Open'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onPressed: () => _storage.shareFile(
                                uri: _lastSavedResult!.uri,
                                mimeType: _lastSavedResult!.mimeType,
                              ),
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (_isExporting)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Generating $_exportingFormatName register...',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const Text(
                  'Select format to save to Downloads/TrackAcademic:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _FormatOptionTile(
                  title: 'CSV (.csv)',
                  subtitle:
                      'Standard spreadsheet format, Unicode/Bengali preserved, formula-protected.',
                  badgeText: 'Spreadsheet',
                  badgeColor: AppColors.success,
                  icon: Icons.table_chart_outlined,
                  onTap: () => _performExport(ExportFormat.csv),
                ),
                const SizedBox(height: 8),
                _FormatOptionTile(
                  title: 'PDF Document (.pdf)',
                  subtitle:
                      'Landscape print-ready table with repeated headers and pagination.',
                  badgeText: 'Print-ready',
                  badgeColor: AppColors.primary,
                  icon: Icons.picture_as_pdf_outlined,
                  onTap: () => _performExport(ExportFormat.pdf),
                ),
                const SizedBox(height: 8),
                _FormatOptionTile(
                  title: 'Word Document (.docx)',
                  subtitle:
                      'Genuine OpenXML Word document with formatted landscape register table.',
                  badgeText: 'Microsoft Word',
                  badgeColor: Colors.indigo,
                  icon: Icons.description_outlined,
                  onTap: () => _performExport(ExportFormat.docx),
                ),
                const SizedBox(height: 8),
                _FormatOptionTile(
                  title: 'Legacy Word (.doc) [Pending Format Decision]',
                  subtitle:
                      'Genuine CFBF binary .doc generation is pending format decision. Modern DOCX is fully supported.',
                  badgeText: 'Pending Decision',
                  badgeColor: AppColors.warning,
                  icon: Icons.pending_actions_outlined,
                  onTap: () => _performExport(ExportFormat.doc),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final VoidCallback onTap;

  const _FormatOptionTile({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, color: badgeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

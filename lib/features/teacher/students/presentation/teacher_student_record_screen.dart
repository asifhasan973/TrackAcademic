import 'package:flutter/material.dart';
import 'package:trackademic/core/services/file_saver/file_saver.dart';
import 'package:trackademic/core/services/student_record_csv_builder.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherStudentRecordScreen extends StatefulWidget {
  final TeacherCourse course;
  final EnrolledStudent student;

  const TeacherStudentRecordScreen({
    super.key,
    required this.course,
    required this.student,
  });

  @override
  State<TeacherStudentRecordScreen> createState() =>
      _TeacherStudentRecordScreenState();
}

class _TeacherStudentRecordScreenState
    extends State<TeacherStudentRecordScreen> {
  static const _service = TeacherAcademicService();

  late Future<TeacherStudentRecord> _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _service.loadStudentRecord(
        courseId: widget.course.id,
        studentId: widget.student.uid,
      );
    });
  }

  Future<void> _exportCsv(TeacherStudentRecord record) async {
    setState(() => _exporting = true);
    try {
      final csvContent = StudentRecordCsvBuilder.build(record);
      final filename = StudentRecordCsvBuilder.generateFilename(
        studentInstitutionId: record.student.institutionId,
        courseCode: record.courseCode,
      );

      final saver = FileSaver();
      final destination = await saver.saveFile(
        filename: filename,
        content: csvContent,
        mimeType: 'text/csv',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Academic record exported: $destination'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export CSV: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _openCorrectionDialog(TeacherStudentMark mark) async {
    final scoreController = TextEditingController(
      text: mark.score.toStringAsFixed(1),
    );
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Correct Mark · ${mark.assessmentName}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student: ${widget.student.displayName} (${widget.student.institutionId})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                'Maximum allowed score: ${mark.maxScore.toStringAsFixed(1)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: scoreController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'New score',
                  suffixText: '/${mark.maxScore.toStringAsFixed(1)}',
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Correction reason',
                  hintText: 'e.g., Regraded question 2; score recalculated',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newScore = double.tryParse(scoreController.text.trim());
              final reason = reasonController.text.trim();

              if (newScore == null ||
                  newScore < 0 ||
                  newScore > mark.maxScore) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Score must be between 0 and ${mark.maxScore.toStringAsFixed(1)}.',
                    ),
                  ),
                );
                return;
              }

              if (reason.isEmpty) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(
                    content: Text('A non-empty correction reason is required.'),
                  ),
                );
                return;
              }

              try {
                await _service.correctPublishedMark(
                  assessmentId: mark.assessmentId,
                  studentId: mark.studentId,
                  newScore: newScore,
                  reason: reason,
                );
                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx, true);
                }
              } on TeacherAcademicServiceException catch (error) {
                if (dialogCtx.mounted) {
                  ScaffoldMessenger.of(
                    dialogCtx,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              }
            },
            child: const Text('Submit correction'),
          ),
        ],
      ),
    );

    scoreController.dispose();
    reasonController.dispose();

    if (result == true) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.student.displayName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<TeacherStudentRecord>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final record = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStudentHeader(record),
                    const SizedBox(height: AppSpacing.large),
                    _buildSummaryMetrics(record),
                    const SizedBox(height: AppSpacing.extraLarge),
                    _buildAttendanceSection(record),
                    const SizedBox(height: AppSpacing.extraLarge),
                    _buildMarksSection(record),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentHeader(TeacherStudentRecord record) {
    final isEnrolled = record.student.isActive;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                record.student.displayName.isNotEmpty
                    ? record.student.displayName[0].toUpperCase()
                    : 'S',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record.student.displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.small),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isEnrolled
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Text(
                          isEnrolled
                              ? 'Active Enrollment'
                              : 'Historical (Inactive)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isEnrolled
                                ? Colors.green[800]
                                : Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.extraSmall),
                  Text(
                    'ID: ${record.student.institutionId} · ${record.student.email}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  Text(
                    'Course: ${record.courseCode} · ${record.courseName}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _exporting ? null : () => _exportCsv(record),
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(TeacherStudentRecord record) {
    final summary = record.attendanceSummary;
    final attPercent = summary?.percentage ?? 0.0;
    final attScore = summary?.attendanceMarks ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'Attendance',
            metric: '${attPercent.toStringAsFixed(1)}%',
            subtitle: summary != null
                ? '${summary.attended}/${summary.total} classes attended · ${attScore.toStringAsFixed(1)}/10 marks'
                : 'No attendance recorded',
            icon: Icons.calendar_today_rounded,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: AppSpacing.medium),
        Expanded(
          child: _MetricCard(
            title: 'Published Marks',
            metric: '${record.percentageScore.toStringAsFixed(1)}%',
            subtitle:
                '${record.totalEarnedScore.toStringAsFixed(1)} / ${record.totalPossibleScore.toStringAsFixed(1)} total points earned',
            icon: Icons.grade_rounded,
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceSection(TeacherStudentRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Attendance History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${record.attendanceRecords.length} sessions',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.medium),
        if (record.attendanceRecords.isEmpty)
          const Material(
            color: AppColors.surface,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.large),
              child: Center(
                child: Text(
                  'No attendance sessions recorded for this student in this course.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          )
        else
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.large),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: record.attendanceRecords.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final att = record.attendanceRecords[index];
                final isPresent = att.status == 'present';
                final isLate = att.status == 'late';

                Color statusColor;
                if (isPresent) {
                  statusColor = Colors.green;
                } else if (isLate) {
                  statusColor = Colors.orange;
                } else {
                  statusColor = Colors.red;
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.1),
                    child: Icon(
                      isPresent
                          ? Icons.check
                          : (isLate ? Icons.access_time : Icons.close),
                      color: statusColor,
                    ),
                  ),
                  title: Text(
                    StudentRecordCsvBuilder.formatDateTime(att.markedAt),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    att.correctionReason != null &&
                            att.correctionReason!.isNotEmpty
                        ? 'Source: ${att.source} · Reason: ${att.correctionReason}'
                        : 'Source: ${att.source}',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      att.status.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMarksSection(TeacherStudentRecord record) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Assessment Marks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${record.marks.length} assessments',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.medium),
        if (record.marks.isEmpty)
          const Material(
            color: AppColors.surface,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.large),
              child: Center(
                child: Text(
                  'No assessment marks found for this student in this course.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          )
        else
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.large),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: record.marks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final mark = record.marks[index];
                final percentage = mark.maxScore <= 0
                    ? 0.0
                    : (mark.score / mark.maxScore) * 100;

                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        mark.assessmentName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: AppSpacing.small),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Text(
                          mark.assessmentType,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mark.assessmentDate.isNotEmpty)
                        Text(
                          'Date: ${mark.assessmentDate}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (mark.previousScore != null)
                        Text(
                          'Corrected from ${mark.previousScore!.toStringAsFixed(1)}: ${mark.correctionReason ?? "No reason given"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.amber,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${mark.score.toStringAsFixed(1)} / ${mark.maxScore.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (mark.published) ...[
                        const SizedBox(width: AppSpacing.small),
                        IconButton(
                          tooltip: 'Correct published mark',
                          icon: const Icon(
                            Icons.edit_note,
                            color: AppColors.primary,
                          ),
                          onPressed: () => _openCorrectionDialog(mark),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String metric;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.metric,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: AppSpacing.medium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    metric,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

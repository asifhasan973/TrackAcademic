import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:trackademic/core/services/attendance_csv_builder.dart';
import 'package:trackademic/core/services/platform_storage_service.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherAttendanceSummaryScreen extends StatefulWidget {
  final TeacherAttendanceSession session;

  const TeacherAttendanceSummaryScreen({required this.session, super.key});

  @override
  State<TeacherAttendanceSummaryScreen> createState() =>
      _TeacherAttendanceSummaryScreenState();
}

class _TeacherAttendanceSummaryScreenState
    extends State<TeacherAttendanceSummaryScreen> {
  static const _service = TeacherAcademicService();

  late Future<_SummaryData> _future;
  bool _exporting = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _reload();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _future = _load();
    if (mounted) {
      setState(() {});
    }
  }

  Future<_SummaryData> _load() async {
    final results = await Future.wait([
      _service.loadCourseStudents(widget.session.courseId),
      _service.loadAttendanceRecords(widget.session),
    ]);

    return _SummaryData(
      students: results[0] as List<EnrolledStudent>,
      records: results[1] as List<TeacherAttendanceRecord>,
    );
  }

  String get _formattedDate {
    final date = widget.session.startedAt;
    if (date == null) {
      return 'N/A';
    }
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.session.courseCode} Attendance Summary'),
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_SummaryData>(
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
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      'Failed to load summary: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return _buildContent(context, data);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, _SummaryData data) {
    final students = data.students;
    final recordsMap = {
      for (final record in data.records) record.studentId: record,
    };

    int presentCount = 0;
    int lateCount = 0;
    int absentCount = 0;

    for (final student in students) {
      final record = recordsMap[student.uid];
      final status = record?.status.toLowerCase() ?? 'absent';
      if (status == 'present') {
        presentCount++;
      } else if (status == 'late') {
        lateCount++;
      } else {
        absentCount++;
      }
    }

    final totalStudents = students.length;
    final attendedCount = presentCount + lateCount;
    final double attendanceRate = totalStudents == 0
        ? 0.0
        : (attendedCount / totalStudents);
    final ratePercentage = (attendanceRate * 100).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSuccessBanner(),
              const SizedBox(height: AppSpacing.large),
              _buildSummaryCards(
                totalStudents: totalStudents,
                presentCount: presentCount,
                lateCount: lateCount,
                absentCount: absentCount,
              ),
              const SizedBox(height: AppSpacing.large),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 800) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _buildAttendanceOverview(
                            ratePercentage: ratePercentage,
                            attendanceRate: attendanceRate,
                            attendedCount: attendedCount,
                            totalStudents: totalStudents,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.regular),
                        Expanded(flex: 4, child: _buildSessionDetails()),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _buildAttendanceOverview(
                        ratePercentage: ratePercentage,
                        attendanceRate: attendanceRate,
                        attendedCount: attendedCount,
                        totalStudents: totalStudents,
                      ),
                      const SizedBox(height: AppSpacing.regular),
                      _buildSessionDetails(),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.large),
              _buildStudentRoster(students, recordsMap),
              const SizedBox(height: AppSpacing.large),
              _buildActions(context, students, recordsMap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.successBackground,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.task_alt_rounded, color: AppColors.success, size: 30),
          SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance session closed',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: AppSpacing.extraSmall),
                Text(
                  'Records are finalized. The course owner may perform audited corrections below.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards({
    required int totalStudents,
    required int presentCount,
    required int lateCount,
    required int absentCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth;

        if (constraints.maxWidth >= 760) {
          cardWidth = (constraints.maxWidth - AppSpacing.regular * 3) / 4;
        } else if (constraints.maxWidth >= 480) {
          cardWidth = (constraints.maxWidth - AppSpacing.regular) / 2;
        } else {
          cardWidth = constraints.maxWidth;
        }

        return Wrap(
          spacing: AppSpacing.regular,
          runSpacing: AppSpacing.regular,
          children: [
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Total enrolled',
                value: '$totalStudents',
                icon: Icons.groups_rounded,
                color: AppColors.primary,
                background: AppColors.informationBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Present',
                value: '$presentCount',
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
                background: AppColors.successBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Late',
                value: '$lateCount',
                icon: Icons.more_time_rounded,
                color: AppColors.warning,
                background: AppColors.warningBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Absent',
                value: '$absentCount',
                icon: Icons.person_off_outlined,
                color: Colors.red,
                background: AppColors.background,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttendanceOverview({
    required int ratePercentage,
    required double attendanceRate,
    required int attendedCount,
    required int totalStudents,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance overview',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.extraLarge),
          Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successBackground,
                border: Border.all(color: AppColors.success, width: 8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$ratePercentage%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Attendance',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.extraLarge),
          LinearProgressIndicator(
            value: attendanceRate.clamp(0.0, 1.0),
            minHeight: 10,
            color: AppColors.success,
            backgroundColor: AppColors.background,
            borderRadius: BorderRadius.circular(100),
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            '$attendedCount out of $totalStudents enrolled students '
            'attended this class.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session details',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          _DetailRow(
            icon: Icons.menu_book_rounded,
            label: 'Course',
            value:
                '${widget.session.courseCode} · ${widget.session.courseName}',
          ),
          const SizedBox(height: AppSpacing.medium),
          _DetailRow(
            icon: Icons.category_outlined,
            label: 'Class type',
            value: widget.session.classType,
          ),
          const SizedBox(height: AppSpacing.medium),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date & time',
            value: _formattedDate,
          ),
          const SizedBox(height: AppSpacing.medium),
          _DetailRow(
            icon: Icons.timer_outlined,
            label: 'Session duration',
            value: '${widget.session.durationMinutes} minutes',
          ),
          const SizedBox(height: AppSpacing.medium),
          _DetailRow(
            icon: Icons.verified_user_outlined,
            label: 'Verification requirements',
            value:
                '${widget.session.requiresPasscode ? "Passcode" : "No passcode"}'
                ' · '
                '${widget.session.requiresGps ? "GPS required" : "No GPS"}',
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRoster(
    List<EnrolledStudent> students,
    Map<String, TeacherAttendanceRecord> recordsMap,
  ) {
    final filteredStudents = _searchQuery.isEmpty
        ? students
        : students.where((s) {
            final nameMatches = s.displayName.toLowerCase().contains(
              _searchQuery,
            );
            final idMatches = s.institutionId.toLowerCase().contains(
              _searchQuery,
            );
            return nameMatches || idMatches;
          }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Student Records',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${students.length} enrolled',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.medium),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by student name or institution ID/roll...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          if (students.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No students are enrolled in this course.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else if (filteredStudents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No matching students',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredStudents.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final student = filteredStudents[index];
                final record = recordsMap[student.uid];
                final status = record?.status.toLowerCase() ?? 'absent';
                final source = record?.source.isNotEmpty == true
                    ? record!.source
                    : 'finalization';
                final markedTime = record?.markedAt != null
                    ? AttendanceCsvBuilder.formatMarkedTime(record!.markedAt)
                    : 'N/A';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.informationBackground,
                    foregroundColor: AppColors.primary,
                    child: Text(
                      student.displayName.isEmpty
                          ? '?'
                          : student.displayName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(
                    student.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${student.institutionId} · Source: $source · Marked: $markedTime'
                    '${record?.correctionReason != null ? "\nCorrection: ${record!.correctionReason}" : ""}',
                  ),
                  isThreeLine: record?.correctionReason != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusBadge(status),
                      const SizedBox(width: AppSpacing.small),
                      IconButton(
                        tooltip: 'Correct status',
                        icon: const Icon(Icons.edit_note_rounded),
                        onPressed: () =>
                            _showCorrectionDialog(student, record, status),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'present':
        bg = AppColors.successBackground;
        fg = AppColors.success;
        label = 'Present';
        break;
      case 'late':
        bg = AppColors.warningBackground;
        fg = AppColors.warning;
        label = 'Late';
        break;
      default:
        bg = Colors.red.withAlpha(25);
        fg = Colors.red;
        label = 'Absent';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Future<void> _showCorrectionDialog(
    EnrolledStudent student,
    TeacherAttendanceRecord? record,
    String currentStatus,
  ) async {
    String selectedStatus = currentStatus;
    if (selectedStatus != 'present' &&
        selectedStatus != 'late' &&
        selectedStatus != 'absent') {
      selectedStatus = 'absent';
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: Text('Correct Attendance: ${student.displayName}'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student ID: ${student.institutionId}\n'
                      'Current status: ${currentStatus.toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Corrected Status',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'present',
                          child: Text('Present'),
                        ),
                        DropdownMenuItem(value: 'late', child: Text('Late')),
                        DropdownMenuItem(
                          value: 'absent',
                          child: Text('Absent'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedStatus = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    TextFormField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Correction Reason',
                        hintText: 'e.g. Verified medical certificate',
                      ),
                      maxLines: 2,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'A correction reason is required for audit.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setDialogState(() => saving = true);

                          try {
                            await _service.correctClosedAttendance(
                              sessionId: widget.session.id,
                              studentId: student.uid,
                              newStatus: selectedStatus,
                              reason: reasonController.text.trim(),
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            if (!mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Attendance for ${student.displayName} '
                                  'corrected to ${selectedStatus.toUpperCase()}.',
                                ),
                              ),
                            );
                            _reload();
                          } on TeacherAcademicServiceException catch (e) {
                            setDialogState(() => saving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Correction'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
  }

  Widget _buildActions(
    BuildContext context,
    List<EnrolledStudent> students,
    Map<String, TeacherAttendanceRecord> recordsMap,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: _exporting ? null : () => _exportCsv(students, recordsMap),
          icon: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_exporting ? 'Exporting...' : 'Download report'),
        ),
        const SizedBox(width: AppSpacing.medium),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.done_rounded),
          label: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _exportCsv(
    List<EnrolledStudent> students,
    Map<String, TeacherAttendanceRecord> recordsMap,
  ) async {
    setState(() => _exporting = true);

    try {
      final csvContent = AttendanceCsvBuilder.build(
        courseCode: widget.session.courseCode,
        courseName: widget.session.courseName,
        sessionDate: widget.session.startedAt,
        classType: widget.session.classType,
        students: students,
        records: recordsMap,
      );

      final filename = AttendanceCsvBuilder.generateFilename(
        courseCode: widget.session.courseCode,
        date: widget.session.startedAt,
      );

      const storage = PlatformStorageService();
      final saved = await storage.saveToDownloads(
        filename: filename,
        bytes: Uint8List.fromList(utf8.encode(csvContent)),
        mimeType: 'text/csv',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${saved.displayPath}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => storage.openFile(
                uri: saved.uri,
                mimeType: saved.mimeType,
              ),
            ),
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
}

class _SummaryData {
  final List<EnrolledStudent> students;
  final List<TeacherAttendanceRecord> records;

  const _SummaryData({required this.students, required this.records});
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 20),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.extraSmall),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

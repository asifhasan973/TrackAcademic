import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/core/services/attendance_csv_builder.dart';
import 'package:trackademic/core/services/file_saver/file_saver.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class CourseAttendanceRegisterScreen extends StatefulWidget {
  final TeacherCourse course;

  const CourseAttendanceRegisterScreen({required this.course, super.key});

  @override
  State<CourseAttendanceRegisterScreen> createState() =>
      _CourseAttendanceRegisterScreenState();
}

class _CourseAttendanceRegisterScreenState
    extends State<CourseAttendanceRegisterScreen> {
  static const _service = TeacherAcademicService();

  late Future<_RegisterData> _future;
  _RegisterData? _currentData;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_RegisterData> _load() async {
    final db = FirebaseFirestore.instance;

    // 1. Load active enrolled students
    final students = await _service.loadCourseStudents(widget.course.id);
    students.sort((a, b) => a.institutionId.compareTo(b.institutionId));

    // 2. Load all closed attendance sessions for this course
    final sessionsSnapshot = await db
        .collection('attendanceSessions')
        .where('courseId', isEqualTo: widget.course.id)
        .where('status', isEqualTo: 'closed')
        .get();

    final sessions = sessionsSnapshot.docs
        .map((d) => TeacherAttendanceSession.fromMap(d.id, d.data()))
        .toList();

    // Sort chronologically from oldest to newest
    sessions.sort((a, b) {
      final aDate = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDate.compareTo(bDate);
    });

    // 3. Load all attendance records for this course in a single query
    final recordsSnapshot = await db
        .collection('attendanceRecords')
        .where('courseId', isEqualTo: widget.course.id)
        .get();

    final matrix = <String, Map<String, String>>{};
    for (final doc in recordsSnapshot.docs) {
      final data = doc.data();
      final studentId = data['studentId'] as String? ?? '';
      final sessionId = data['sessionId'] as String? ?? '';
      final status = (data['status'] as String? ?? 'absent').toLowerCase();

      if (studentId.isNotEmpty && sessionId.isNotEmpty) {
        matrix.putIfAbsent(studentId, () => {})[sessionId] = status;
      }
    }

    final data = _RegisterData(
      course: widget.course,
      students: students,
      sessions: sessions,
      matrix: matrix,
    );
    _currentData = data;
    return data;
  }

  Future<void> _exportCsv(_RegisterData data) async {
    setState(() => _exporting = true);

    try {
      final csvContent = AttendanceCsvBuilder.buildFullRegisterCsv(
        courseCode: data.course.code,
        courseName: data.course.name,
        students: data.students,
        sessions: data.sessions,
        matrix: data.matrix,
      );

      final filename = AttendanceCsvBuilder.generateFullRegisterFilename(
        courseCode: data.course.code,
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
            content: Text('Course register exported: $destination'),
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

  Future<void> _correctCell({
    required _RegisterData data,
    required EnrolledStudent student,
    required TeacherAttendanceSession session,
    required String currentStatus,
  }) async {
    final formKey = GlobalKey<FormState>();
    var selectedStatus = currentStatus;
    final reasonController = TextEditingController(
      text: 'Teacher correction from course attendance matrix',
    );
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Correct attendance for ${student.displayName}'),
              content: SizedBox(
                width: 440,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Class: ${session.courseCode} · ${session.classType} (${_formatShortDate(session.startedAt)})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        const Text(
                          'New Status',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: selectedStatus,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'present',
                              child: Text('Present'),
                            ),
                            DropdownMenuItem(
                              value: 'late',
                              child: Text('Late'),
                            ),
                            DropdownMenuItem(
                              value: 'absent',
                              child: Text('Absent'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setDialogState(
                                      () => selectedStatus = value,
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        TextFormField(
                          controller: reasonController,
                          enabled: !saving,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Correction Reason *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 4) {
                              return 'Please enter a valid correction reason (min 4 chars).';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => saving = true);

                          try {
                            await _service.correctClosedAttendance(
                              sessionId: session.id,
                              studentId: student.uid,
                              newStatus: selectedStatus,
                              reason: reasonController.text.trim(),
                            );

                            if (mounted) {
                              setState(() {
                                data.matrix.putIfAbsent(
                                  student.uid,
                                  () => {},
                                )[session.id] = selectedStatus;
                              });
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${student.displayName} marked ${selectedStatus.toUpperCase()}.',
                                  ),
                                ),
                              );
                            }
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course.code} Attendance Register'),
        actions: [
          if (_currentData != null)
            IconButton(
              tooltip: 'Download CSV',
              onPressed: _exporting ? null : () => _exportCsv(_currentData!),
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_RegisterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.extraLarge),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      'Failed to load attendance register: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return _buildRegisterView(data);
        },
      ),
    );
  }

  Widget _buildRegisterView(_RegisterData data) {
    if (data.students.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.extraLarge),
          child: Text(
            'No active students enrolled in this course.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    if (data.sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.extraLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_busy_rounded,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.medium),
              const Text(
                'No finalized classes yet for this course.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'Classes will appear in this register once attendance sessions are closed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // Compute overall course percentage
    var totalPossible = data.students.length * data.sessions.length;
    var totalAttended = 0;
    for (final student in data.students) {
      final studentMap = data.matrix[student.uid] ?? const {};
      for (final session in data.sessions) {
        final status = (studentMap[session.id] ?? 'absent').toLowerCase();
        if (status == 'present' || status == 'late') {
          totalAttended++;
        }
      }
    }
    final avgCoursePercentage = totalPossible > 0
        ? (totalAttended / totalPossible) * 100
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header summary banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.regular),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: AppSpacing.large,
              runSpacing: AppSpacing.medium,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.course.code} · ${data.course.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      'Course ID: ${data.course.id}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatPill('Total Classes', '${data.sessions.length}'),
                    const SizedBox(width: AppSpacing.medium),
                    _buildStatPill(
                      'Enrolled Students',
                      '${data.students.length}',
                    ),
                    const SizedBox(width: AppSpacing.medium),
                    _buildStatPill(
                      'Avg Attendance',
                      '${avgCoursePercentage.toStringAsFixed(1)}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.medium),

          // Instruction hint
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '💡 Tap any attendance cell to correct attendance status.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.small),

          // Scrollable Excel-like Table
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              side: const BorderSide(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  AppColors.primary.withValues(alpha: 0.05),
                ),
                columnSpacing: 20,
                horizontalMargin: 16,
                columns: [
                  const DataColumn(
                    label: Text(
                      'Student Name',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const DataColumn(
                    label: Text(
                      'Roll / ID',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (var i = 0; i < data.sessions.length; i++)
                    DataColumn(
                      label: Tooltip(
                        message:
                            'Class ${i + 1}\n${data.sessions[i].classType}\n${_formatFullDateTime(data.sessions[i].startedAt)}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Class ${i + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _formatShortDate(data.sessions[i].startedAt),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const DataColumn(
                    label: Text(
                      'Attended',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const DataColumn(
                    label: Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const DataColumn(
                    label: Text(
                      'Percentage',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: data.students.map((student) {
                  final studentStatuses = data.matrix[student.uid] ?? const {};
                  var attended = 0;
                  final total = data.sessions.length;

                  final cells = <DataCell>[
                    DataCell(
                      Text(
                        student.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(Text(student.institutionId)),
                  ];

                  for (final session in data.sessions) {
                    final status = (studentStatuses[session.id] ?? 'absent')
                        .toLowerCase();
                    if (status == 'present' || status == 'late') {
                      attended++;
                    }

                    cells.add(
                      DataCell(
                        InkWell(
                          onTap: () => _correctCell(
                            data: data,
                            student: student,
                            session: session,
                            currentStatus: status,
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: _buildCellIndicator(status),
                          ),
                        ),
                      ),
                    );
                  }

                  final percentage = total > 0 ? (attended / total) * 100 : 0.0;

                  cells.add(DataCell(Text('$attended')));
                  cells.add(DataCell(Text('$total')));
                  cells.add(
                    DataCell(
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: percentage >= 75
                              ? AppColors.success
                              : (percentage >= 50
                                    ? AppColors.warning
                                    : AppColors.danger),
                        ),
                      ),
                    ),
                  );

                  return DataRow(cells: cells);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildCellIndicator(String status) {
    if (status == 'present') {
      return const Tooltip(
        message: 'Present',
        child: Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 20,
        ),
      );
    } else if (status == 'late') {
      return const Tooltip(
        message: 'Late (Attended)',
        child: Icon(
          Icons.watch_later_rounded,
          color: AppColors.warning,
          size: 20,
        ),
      );
    } else {
      return const Tooltip(
        message: 'Absent',
        child: Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
      );
    }
  }

  static String _formatShortDate(DateTime? dt) {
    if (dt == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  static String _formatFullDateTime(DateTime? dt) {
    if (dt == null) return '';
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _RegisterData {
  final TeacherCourse course;
  final List<EnrolledStudent> students;
  final List<TeacherAttendanceSession> sessions;
  final Map<String, Map<String, String>> matrix;

  _RegisterData({
    required this.course,
    required this.students,
    required this.sessions,
    required this.matrix,
  });
}

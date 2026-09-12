import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/student/courses/presentation/student_course_detail_screen.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final String? highlightSessionId;

  const StudentAttendanceScreen({this.highlightSessionId, super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  static const _service = StudentAcademicService();
  static const _academicService = AcademicService();

  late Stream<List<StudentAttendanceSession>> _sessionsStream;
  late Future<_StudentAttendanceOverviewData> _overviewFuture;

  final Set<String> _submittingSessionIds = <String>{};
  final Set<String> _submittedSessionIds = <String>{};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sessionsStream = _service.streamActiveSessions();
    _overviewFuture = _loadOverview();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _reload() {
    setState(() {
      _sessionsStream = _service.streamActiveSessions();
      _overviewFuture = _loadOverview();
    });
  }

  Future<_StudentAttendanceOverviewData> _loadOverview() async {
    final courses = await _academicService.loadCurrentCourses();
    final summaries = await _academicService.loadAttendanceSummaries();
    final records = await _service.loadMyAttendanceRecords();

    final summaryMap = <String, StudentAttendanceSummary>{};
    for (final s in summaries) {
      summaryMap[s.courseId] = s;
    }

    return _StudentAttendanceOverviewData(
      courses: courses,
      summaries: summaryMap,
      records: records,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Attendance',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const Text(
                'Mark attendance for active sessions and tap any course to view details.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.large),

              // Active sessions header
              const Text(
                'Active sessions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.medium),

              // Real-time active sessions
              StreamBuilder<List<StudentAttendanceSession>>(
                stream: _sessionsStream,
                builder: (context, sessionSnapshot) {
                  if (sessionSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !sessionSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (sessionSnapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Failed to load active sessions: ${sessionSnapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  final sessions = sessionSnapshot.data ?? const [];

                  if (sessions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No active attendance session is available.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return FutureBuilder<_StudentAttendanceOverviewData>(
                    future: _overviewFuture,
                    builder: (context, overviewSnapshot) {
                      final records =
                          overviewSnapshot.data?.records ?? const [];

                      return Column(
                        children: [
                          for (final session in sessions) ...[
                            _SessionCard(
                              session: session,
                              isHighlighted:
                                  session.id == widget.highlightSessionId,
                              isAlreadySubmitted:
                                  _submittedSessionIds.contains(session.id) ||
                                  records.any(
                                    (r) =>
                                        r.sessionId == session.id &&
                                        r.status != 'waiting',
                                  ),
                              isSubmitting: _submittingSessionIds.contains(
                                session.id,
                              ),
                              onSubmit: () => _submit(session),
                            ),
                            const SizedBox(height: AppSpacing.regular),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: AppSpacing.extraLarge),

              // Enrolled Course Cards Section
              const Text(
                'Enrolled Courses',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.extraSmall),
              const Text(
                'Tap a course to view detailed attendance history and statistics.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.medium),

              FutureBuilder<_StudentAttendanceOverviewData>(
                future: _overviewFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done &&
                      !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text(
                      'Failed to load courses: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    );
                  }

                  final data = snapshot.data!;
                  if (data.courses.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'You are not enrolled in any course yet.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final course in data.courses) ...[
                        _buildCourseAttendanceCard(
                          course: course,
                          summary: data.summaries[course.id],
                        ),
                        const SizedBox(height: AppSpacing.medium),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseAttendanceCard({
    required AcademicCourse course,
    required StudentAttendanceSummary? summary,
  }) {
    final attended = summary?.attended ?? 0;
    final total = summary?.total ?? 0;
    final percentage = summary?.percentage ?? 0.0;
    final isSafe = percentage >= 75;
    final progress = total > 0 ? (attended / total).clamp(0.0, 1.0) : 0.0;
    final progressColor = isSafe ? AppColors.success : AppColors.danger;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.large),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => StudentCourseDetailScreen(
                courseId: course.id,
                courseCode: course.code,
                courseName: course.name,
                initialTabIndex: 0,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.informationBackground,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      course.code,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.medium),
                  Expanded(
                    child: Text(
                      course.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    total > 0 ? '${percentage.toStringAsFixed(0)}%' : '—',
                    style: TextStyle(
                      color: total > 0
                          ? progressColor
                          : AppColors.textSecondary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.small),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    total > 0
                        ? '$attended of $total classes attended'
                        : 'No attendance records yet',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (course.teacherName.isNotEmpty)
                    Text(
                      course.teacherName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(StudentAttendanceSession session) async {
    if (_submittingSessionIds.contains(session.id)) {
      return;
    }

    String? passcode;

    if (session.requiresPasscode) {
      final controller = TextEditingController();

      passcode = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Passcode'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Attendance passcode'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      controller.dispose();

      if (passcode == null || passcode.isEmpty) {
        return;
      }
    }

    setState(() {
      _submittingSessionIds.add(session.id);
    });

    try {
      await _service.submitAttendance(session: session, passcode: passcode);

      if (!mounted) {
        return;
      }

      setState(() {
        _submittedSessionIds.add(session.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance submitted successfully.'),
          backgroundColor: AppColors.success,
        ),
      );

      _reload();
    } on StudentAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingSessionIds.remove(session.id);
        });
      }
    }
  }
}

class _StudentAttendanceOverviewData {
  final List<AcademicCourse> courses;
  final Map<String, StudentAttendanceSummary> summaries;
  final List<StudentAttendanceRecord> records;

  const _StudentAttendanceOverviewData({
    required this.courses,
    required this.summaries,
    required this.records,
  });
}

class _SessionCard extends StatelessWidget {
  final StudentAttendanceSession session;
  final bool isHighlighted;
  final bool isAlreadySubmitted;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _SessionCard({
    required this.session,
    required this.isHighlighted,
    required this.isAlreadySubmitted,
    required this.isSubmitting,
    required this.onSubmit,
  });

  bool get isExpired {
    final endsAt = session.endsAt;
    if (endsAt == null) {
      return false;
    }
    final now = DateTime.now();
    return now.isAfter(endsAt) && !session.allowLateEntry;
  }

  bool get canSubmit {
    return !isExpired && !isAlreadySubmitted && !isSubmitting;
  }

  String get remaining {
    final endsAt = session.endsAt;

    if (endsAt == null) {
      return '--:--';
    }

    final duration = endsAt.difference(DateTime.now());

    if (duration.isNegative) {
      return session.allowLateEntry
          ? 'Late entry accepted'
          : 'Expired (closed)';
    }

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  String get _dateAndTimeString {
    final start = session.startedAt;
    if (start == null) {
      return 'Today';
    }
    final now = DateTime.now();
    final isToday =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final datePart = isToday
        ? 'Today'
        : '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final timePart =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return '$datePart · $timePart';
  }

  @override
  Widget build(BuildContext context) {
    final requirements = <String>[
      if (session.requiresPasscode) 'Passcode',
      if (session.requiresGps) 'GPS verified',
    ];

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(
          color: isHighlighted ? AppColors.primary : AppColors.border,
          width: isHighlighted ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 560;

            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${session.courseCode} · ${session.courseName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_dateAndTimeString · ${session.classType} (${session.durationMinutes} min)',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: $remaining',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isAlreadySubmitted
                        ? AppColors.success
                        : canSubmit
                        ? AppColors.textPrimary
                        : Colors.red,
                  ),
                ),
                if (requirements.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Requirements: ${requirements.join(", ")}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            );

            final submitButton = FilledButton.icon(
              onPressed: canSubmit ? onSubmit : null,
              icon: isSubmitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                isAlreadySubmitted
                    ? 'Submitted'
                    : isSubmitting
                    ? 'Submitting...'
                    : 'Submit attendance',
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: AppSpacing.regular),
                  submitButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: AppSpacing.medium),
                submitButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

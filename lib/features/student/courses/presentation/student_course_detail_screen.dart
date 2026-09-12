import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentCourseDetailScreen extends StatefulWidget {
  final String courseId;
  final String? courseCode;
  final String? courseName;
  final int initialTabIndex;
  final String? highlightSessionId;
  final String? highlightAssessmentId;

  const StudentCourseDetailScreen({
    required this.courseId,
    this.courseCode,
    this.courseName,
    this.initialTabIndex = 0,
    this.highlightSessionId,
    this.highlightAssessmentId,
    super.key,
  });

  @override
  State<StudentCourseDetailScreen> createState() =>
      _StudentCourseDetailScreenState();
}

class _StudentCourseDetailScreenState extends State<StudentCourseDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _academicService = AcademicService();
  static const _studentAcademicService = StudentAcademicService();

  late final TabController _tabController;
  late Future<_CourseDetailBundle> _future;

  final Set<String> _submittingSessionIds = <String>{};
  final Set<String> _submittedSessionIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _loadBundle();
    });
  }

  Future<_CourseDetailBundle> _loadBundle() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const AcademicServiceException('You are not signed in.');
    }

    final db = FirebaseFirestore.instance;

    // 1. Load course doc
    final courseDoc = await db.collection('courses').doc(widget.courseId).get();
    if (!courseDoc.exists) {
      throw const AcademicServiceException('Course not found.');
    }
    final course = AcademicCourse.fromMap(courseDoc.id, courseDoc.data()!);

    // 2. Load attendance summary for student
    StudentAttendanceSummary? summary;
    final summaryDoc = await db
        .collection('attendanceSummaries')
        .doc('${widget.courseId}_$uid')
        .get();
    if (summaryDoc.exists && summaryDoc.data() != null) {
      summary = StudentAttendanceSummary.fromMap(
        summaryDoc.id,
        summaryDoc.data()!,
      );
    }

    // 3. Load attendance records for student in this course
    final recordsSnap = await db
        .collection('attendanceRecords')
        .where('courseId', isEqualTo: widget.courseId)
        .where('studentId', isEqualTo: uid)
        .get();
    final records = recordsSnap.docs
        .map((doc) => StudentAttendanceRecord.fromMap(doc.id, doc.data()))
        .toList();
    records.sort((a, b) {
      final aTime = a.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.markedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    // 4. Load published marks for student in this course
    final allMarks = await _academicService.loadPublishedMarks();
    final marks = allMarks.where((m) => m.courseId == widget.courseId).toList();
    marks.sort((a, b) => a.assessmentName.compareTo(b.assessmentName));

    // 5. Load schedules for this course
    final schedulesSnap = await db
        .collection('schedules')
        .where('courseId', isEqualTo: widget.courseId)
        .get();
    final schedules = schedulesSnap.docs
        .map((doc) => ClassScheduleEntry.fromMap(doc.id, doc.data()))
        .toList();
    schedules.sort((a, b) {
      final dayComp = a.dayIndex.compareTo(b.dayIndex);
      if (dayComp != 0) return dayComp;
      return a.startTime.compareTo(b.startTime);
    });

    // 6. Load active attendance sessions for this course
    final activeSessionsSnap = await db
        .collection('attendanceSessions')
        .where('courseId', isEqualTo: widget.courseId)
        .where('status', isEqualTo: 'active')
        .get();
    final activeSessions = activeSessionsSnap.docs
        .map((doc) => StudentAttendanceSession.fromMap(doc.id, doc.data()))
        .toList();

    return _CourseDetailBundle(
      course: course,
      summary: summary,
      records: records,
      marks: marks,
      schedules: schedules,
      activeSessions: activeSessions,
    );
  }

  Future<void> _submitAttendance(StudentAttendanceSession session) async {
    if (_submittingSessionIds.contains(session.id)) return;

    String? passcode;
    if (session.requiresPasscode) {
      final controller = TextEditingController();
      passcode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enter Passcode'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Attendance passcode'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (passcode == null || passcode.isEmpty) return;
    }

    setState(() {
      _submittingSessionIds.add(session.id);
    });

    try {
      await _studentAcademicService.submitAttendance(
        session: session,
        passcode: passcode,
      );

      if (!mounted) return;

      setState(() {
        _submittedSessionIds.add(session.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance recorded successfully!'),
          backgroundColor: AppColors.success,
        ),
      );

      _reload();
    } on StudentAcademicServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseCode ?? 'Course Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_CourseDetailBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
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
                      size: 48,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      'Failed to load course details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  // Top Course Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.large,
                      AppSpacing.medium,
                      AppSpacing.large,
                      AppSpacing.small,
                    ),
                    child: _buildCourseHeader(data.course),
                  ),

                  // Active Session Card if any
                  if (data.activeSessions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.large,
                        vertical: AppSpacing.small,
                      ),
                      child: Column(
                        children: [
                          for (final session in data.activeSessions)
                            _buildActiveSessionBanner(session, data.records),
                        ],
                      ),
                    ),

                  // Tab Bar
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.fact_check_rounded, size: 20),
                        text: 'Attendance',
                      ),
                      Tab(
                        icon: Icon(Icons.bar_chart_rounded, size: 20),
                        text: 'Marks',
                      ),
                      Tab(
                        icon: Icon(Icons.calendar_month_rounded, size: 20),
                        text: 'Timetable',
                      ),
                    ],
                  ),

                  // Tab Bar View
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAttendanceTab(data),
                        _buildMarksTab(data),
                        _buildTimetableTab(data),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCourseHeader(AcademicCourse course) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
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
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.medium),
              Expanded(
                child: Text(
                  course.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.medium),
          Wrap(
            spacing: AppSpacing.large,
            runSpacing: AppSpacing.small,
            children: [
              if (course.teacherName.isNotEmpty)
                _iconLabel(Icons.person_outline_rounded, course.teacherName),
              if (course.room.isNotEmpty)
                _iconLabel(Icons.meeting_room_outlined, course.room),
              if (course.department.isNotEmpty)
                _iconLabel(Icons.school_outlined, course.department),
              if (course.semester.isNotEmpty)
                _iconLabel(
                  Icons.layers_outlined,
                  '${course.semester} Semester',
                ),
              if (course.batch.isNotEmpty || course.section.isNotEmpty)
                _iconLabel(
                  Icons.group_outlined,
                  'Batch ${course.batch} (${course.section})',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconLabel(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildActiveSessionBanner(
    StudentAttendanceSession session,
    List<StudentAttendanceRecord> records,
  ) {
    final isSubmitted =
        _submittedSessionIds.contains(session.id) ||
        records.any((r) => r.sessionId == session.id && r.status != 'waiting');
    final isSubmitting = _submittingSessionIds.contains(session.id);
    final isHighlighted = session.id == widget.highlightSessionId;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: isHighlighted
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: isHighlighted ? AppColors.primary : AppColors.success,
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.successBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSubmitted ? Icons.check_circle_rounded : Icons.sensors_rounded,
              color: isSubmitted ? AppColors.success : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Live Attendance Session',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
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
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${session.classType} class · Ends ${session.endsAt != null ? _formatTime(session.endsAt!) : 'soon'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.small),
          if (isSubmitted)
            const Chip(
              label: Text('Submitted'),
              avatar: Icon(Icons.check, size: 16, color: AppColors.success),
              backgroundColor: AppColors.successBackground,
            )
          else
            FilledButton.icon(
              onPressed: isSubmitting ? null : () => _submitAttendance(session),
              icon: isSubmitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.touch_app_rounded, size: 16),
              label: Text(isSubmitting ? 'Submitting...' : 'Mark Present'),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab(_CourseDetailBundle data) {
    final summary = data.summary;
    final records = data.records;

    final attended = summary?.attended ?? 0;
    final total = summary?.total ?? 0;
    final percentage = summary?.percentage ?? 0.0;
    final marks = summary?.attendanceMarks ?? 0.0;
    final isSafe = percentage >= 75;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Attendance summary cards
          Container(
            padding: const EdgeInsets.all(AppSpacing.regular),
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
                      'Attendance Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isSafe ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.small),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (attended / total).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation(
                      isSafe ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricItem(
                      'Classes Attended',
                      '$attended / $total',
                      Icons.check_circle_outline_rounded,
                    ),
                    _metricItem(
                      'Attendance Marks',
                      '${marks.toStringAsFixed(1)} / 10',
                      Icons.calculate_outlined,
                    ),
                    _metricItem(
                      'Status',
                      isSafe ? 'Eligible (>=75%)' : 'Short Attendance',
                      isSafe
                          ? Icons.thumb_up_outlined
                          : Icons.warning_amber_rounded,
                      color: isSafe ? AppColors.success : AppColors.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.large),

          // Date-wise Attendance History
          const Text(
            'Attendance History',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.small),

          if (records.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.extraLarge),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 40,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(height: AppSpacing.medium),
                  Text(
                    'No attendance records recorded yet for this course.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final isPresent = record.status == 'present';
                  final isLate = record.status == 'late';

                  final Color statusColor;
                  final IconData statusIcon;
                  final String statusLabel;

                  if (isPresent) {
                    statusColor = AppColors.success;
                    statusIcon = Icons.check_circle_rounded;
                    statusLabel = 'Present';
                  } else if (isLate) {
                    statusColor = AppColors.warning;
                    statusIcon = Icons.schedule_rounded;
                    statusLabel = 'Late';
                  } else {
                    statusColor = AppColors.danger;
                    statusIcon = Icons.cancel_rounded;
                    statusLabel = 'Absent';
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    title: Text(
                      record.markedAt != null
                          ? _formatDateTime(record.markedAt!)
                          : 'Finalized Absent',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      record.source.isNotEmpty
                          ? 'Source: ${record.source}'
                          : 'Recorded',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricItem(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildMarksTab(_CourseDetailBundle data) {
    final marks = data.marks;

    if (marks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.extraLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.bar_chart_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              SizedBox(height: AppSpacing.medium),
              Text(
                'No published marks available for this course yet.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    double totalEarned = 0;
    double totalMax = 0;
    for (final m in marks) {
      totalEarned += m.score;
      totalMax += m.maxScore;
    }
    final overallPercentage = totalMax > 0
        ? (totalEarned / totalMax) * 100
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marks summary card
          Container(
            padding: const EdgeInsets.all(AppSpacing.regular),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Course Marks Overview',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total: ${totalEarned.toStringAsFixed(1)} / ${totalMax.toStringAsFixed(1)} points across ${marks.length} assessments',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.informationBackground,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Text(
                    '${overallPercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.large),

          const Text(
            'Published Assessments',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.small),

          for (final mark in marks) ...[
            _buildMarkCard(mark),
            const SizedBox(height: AppSpacing.small),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkCard(StudentMarkRecord mark) {
    final isHighlighted = mark.assessmentId == widget.highlightAssessmentId;
    final percentage = mark.maxScore > 0
        ? (mark.score / mark.maxScore) * 100
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(
          color: isHighlighted ? AppColors.primary : AppColors.border,
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mark.assessmentName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${mark.score.toStringAsFixed(1)} / ${mark.maxScore.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: percentage >= 50
                      ? AppColors.successBackground
                      : AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: percentage >= 50
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          if (mark.previousScore != null &&
              mark.correctionReason != null &&
              mark.correctionReason!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.small),
            Container(
              padding: const EdgeInsets.all(AppSpacing.small),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(AppRadius.small),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Corrected from ${mark.previousScore}: "${mark.correctionReason}"',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimetableTab(_CourseDetailBundle data) {
    final schedules = data.schedules;

    if (schedules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.extraLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.calendar_today_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              SizedBox(height: AppSpacing.medium),
              Text(
                'No regular class timing configured for this course.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Class Timings',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          for (final schedule in schedules) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.regular),
              margin: const EdgeInsets.only(bottom: AppSpacing.small),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.informationBackground,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      schedule.day,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.medium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${schedule.startTime} - ${schedule.endTime}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${schedule.room} · ${schedule.classType}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String _formatDateTime(DateTime date) {
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
    final month = months[date.month - 1];
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} $month ${date.year}, $hour:$minute $period';
  }
}

class _CourseDetailBundle {
  final AcademicCourse course;
  final StudentAttendanceSummary? summary;
  final List<StudentAttendanceRecord> records;
  final List<StudentMarkRecord> marks;
  final List<ClassScheduleEntry> schedules;
  final List<StudentAttendanceSession> activeSessions;

  const _CourseDetailBundle({
    required this.course,
    required this.summary,
    required this.records,
    required this.marks,
    required this.schedules,
    required this.activeSessions,
  });
}

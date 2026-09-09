import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentDashboardScreen extends StatefulWidget {
  final VoidCallback onOpenAttendance;
  final VoidCallback onOpenMarks;
  final VoidCallback onOpenSchedule;

  const StudentDashboardScreen({
    required this.onOpenAttendance,
    required this.onOpenMarks,
    required this.onOpenSchedule,
    super.key,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  static const _academicService = AcademicService();
  static const _authService = AuthService();

  late Future<StudentAcademicOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _overviewFuture = _academicService.loadStudentOverview();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Student';

    return FutureBuilder<StudentAcademicOverview>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(displayName),
                  const SizedBox(height: AppSpacing.large),
                  const _PrivacyBanner(),
                  const SizedBox(height: AppSpacing.large),
                  if (snapshot.connectionState != ConnectionState.done)
                    const _LoadingCard()
                  else if (snapshot.hasError)
                    _ErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: _retry,
                    )
                  else if (snapshot.hasData) ...[
                    _buildSummaryCards(snapshot.data!),
                    const SizedBox(height: AppSpacing.large),
                    _buildQuickActions(),
                    const SizedBox(height: AppSpacing.large),
                    _buildMainContent(snapshot.data!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, $displayName',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: AppSpacing.small),
        const Text(
          'Here is your academic overview for today.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(StudentAcademicOverview overview) {
    final attendanceValue = overview.totalClasses == 0
        ? '—'
        : '${overview.overallAttendance.toStringAsFixed(0)}%';

    final attendanceDetail = overview.totalClasses == 0
        ? 'No attendance records yet'
        : '${overview.attendedClasses} of ${overview.totalClasses} classes';

    final attendanceMarksValue = overview.attendance.isEmpty
        ? '—'
        : '${overview.averageAttendanceMarks.toStringAsFixed(1)}/10';

    final marksValue = overview.marks.isEmpty
        ? '—'
        : '${overview.averageCtPercentage.toStringAsFixed(1)}%';

    final todaySchedules = _todaySchedules(overview.schedules);

    final todayClassesValue = todaySchedules.length.toString();

    final todayDetail = todaySchedules.isEmpty
        ? 'No classes scheduled today'
        : 'Next: ${todaySchedules.first.startTime}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth;

        if (constraints.maxWidth >= 900) {
          cardWidth = (constraints.maxWidth - AppSpacing.regular * 3) / 4;
        } else if (constraints.maxWidth >= 560) {
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
              child: _MetricCard(
                label: 'Overall attendance',
                value: attendanceValue,
                detail: attendanceDetail,
                icon: Icons.fact_check_rounded,
                foreground: AppColors.success,
                background: AppColors.successBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Attendance marks',
                value: attendanceMarksValue,
                detail: overview.attendance.isEmpty
                    ? 'No attendance marks yet'
                    : 'Average across ${overview.attendance.length} courses',
                icon: Icons.calculate_rounded,
                foreground: AppColors.primary,
                background: AppColors.informationBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'CT average',
                value: marksValue,
                detail: overview.marks.isEmpty
                    ? 'No published marks yet'
                    : '${overview.marks.length} published assessments',
                icon: Icons.bar_chart_rounded,
                foreground: AppColors.warning,
                background: AppColors.warningBackground,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                label: 'Today’s classes',
                value: todayClassesValue,
                detail: todayDetail,
                icon: Icons.calendar_month_rounded,
                foreground: AppColors.secondary,
                background: AppColors.backgroundSoft,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
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
            'Quick actions',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.regular),
          LayoutBuilder(
            builder: (context, constraints) {
              final attendanceButton = OutlinedButton.icon(
                onPressed: widget.onOpenAttendance,
                icon: const Icon(Icons.location_on_rounded),
                label: const Text('Mark attendance'),
              );

              final marksButton = OutlinedButton.icon(
                onPressed: widget.onOpenMarks,
                icon: const Icon(Icons.analytics_rounded),
                label: const Text('View marks'),
              );

              final scheduleButton = OutlinedButton.icon(
                onPressed: widget.onOpenSchedule,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('View schedule'),
              );

              if (constraints.maxWidth >= 680) {
                return Row(
                  children: [
                    Expanded(child: attendanceButton),
                    const SizedBox(width: AppSpacing.medium),
                    Expanded(child: marksButton),
                    const SizedBox(width: AppSpacing.medium),
                    Expanded(child: scheduleButton),
                  ],
                );
              }

              return Column(
                children: [
                  SizedBox(width: double.infinity, child: attendanceButton),
                  const SizedBox(height: AppSpacing.small),
                  SizedBox(width: double.infinity, child: marksButton),
                  const SizedBox(height: AppSpacing.small),
                  SizedBox(width: double.infinity, child: scheduleButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(StudentAcademicOverview overview) {
    final attendanceCard = _AttendanceByCourseCard(
      summaries: overview.attendance,
    );

    final scheduleCard = _TodayScheduleCard(
      schedules: _todaySchedules(overview.schedules),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: attendanceCard),
              const SizedBox(width: AppSpacing.regular),
              Expanded(flex: 5, child: scheduleCard),
            ],
          );
        }

        return Column(
          children: [
            attendanceCard,
            const SizedBox(height: AppSpacing.regular),
            scheduleCard,
          ],
        );
      },
    );
  }

  List<ClassScheduleEntry> _todaySchedules(List<ClassScheduleEntry> schedules) {
    final weekday = DateTime.now().weekday;

    final dayIndex = weekday == DateTime.sunday ? 0 : weekday;

    final result = schedules
        .where((schedule) => schedule.dayIndex == dayIndex)
        .toList();

    result.sort((a, b) => a.startTime.compareTo(b.startTime));

    return result;
  }

  void _retry() {
    setState(() {
      _overviewFuture = _academicService.loadStudentOverview();
    });
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.informationBackground,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.primary),
          SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Text(
              'Your academic records are private. Only you and '
              'authorized teachers can view them.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color foreground;
  final Color background;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.foreground,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(icon, color: foreground),
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          Text(
            detail,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AttendanceByCourseCard extends StatelessWidget {
  final List<StudentAttendanceSummary> summaries;

  const _AttendanceByCourseCard({required this.summaries});

  @override
  Widget build(BuildContext context) {
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
            'Attendance by course',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          const Text(
            'Minimum recommended attendance is 75%.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.regular),
          if (summaries.isEmpty)
            const _EmptyState(
              icon: Icons.fact_check_outlined,
              message: 'No attendance records are available yet.',
            )
          else
            for (var index = 0; index < summaries.length; index++) ...[
              _AttendanceRow(summary: summaries[index]),
              if (index != summaries.length - 1) const Divider(),
            ],
        ],
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final StudentAttendanceSummary summary;

  const _AttendanceRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final isSafe = summary.percentage >= 75;

    final progressColor = isSafe ? AppColors.success : AppColors.danger;

    final progress = (summary.percentage / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.courseCode,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      summary.courseName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${summary.percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: progressColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            color: progressColor,
            backgroundColor: AppColors.border,
            borderRadius: BorderRadius.circular(AppRadius.circular),
          ),
          const SizedBox(height: AppSpacing.extraSmall),
          Text(
            '${summary.attended} of ${summary.total} classes attended',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TodayScheduleCard extends StatelessWidget {
  final List<ClassScheduleEntry> schedules;

  const _TodayScheduleCard({required this.schedules});

  @override
  Widget build(BuildContext context) {
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
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Today’s schedule',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.calendar_today_rounded, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.regular),
          if (schedules.isEmpty)
            const _EmptyState(
              icon: Icons.event_busy_outlined,
              message: 'No classes are scheduled for today.',
            )
          else
            for (var index = 0; index < schedules.length; index++) ...[
              _ScheduleRow(schedule: schedules[index]),
              if (index != schedules.length - 1) const Divider(),
            ],
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final ClassScheduleEntry schedule;

  const _ScheduleRow({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.medium),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
            decoration: BoxDecoration(
              color: AppColors.informationBackground,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Text(
              schedule.startTime,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.courseCode,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${schedule.courseName} · ${schedule.room}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.schedule_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.extraLarge),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 42, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.medium),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.extraLarge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 44,
            color: AppColors.danger,
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.medium),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

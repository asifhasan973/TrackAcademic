import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/student/courses/presentation/student_course_detail_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenMarks;
  final VoidCallback? onOpenSchedule;

  const StudentDashboardScreen({
    this.onOpenAttendance,
    this.onOpenMarks,
    this.onOpenSchedule,
    super.key,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  static const _academicService = AcademicService();
  static const _authService = AuthService();
  static const _studentAcademicService = StudentAcademicService();

  late Future<List<ClassScheduleEntry>> _schedulesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _schedulesFuture = _academicService.loadCurrentSchedules();
    });
  }

  List<ClassScheduleEntry> _getTodaySchedules(
    List<ClassScheduleEntry> schedules,
  ) {
    final now = DateTime.now();
    final weekday = now.weekday;
    final dayIndex = weekday == DateTime.sunday ? 0 : weekday;

    final todayList = schedules.where((s) => s.dayIndex == dayIndex).toList();
    todayList.sort((a, b) => a.startTime.compareTo(b.startTime));
    return todayList;
  }

  String _formatTodayDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final dayName = weekdays[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  Future<void> _joinCourse() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Join code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Request'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (code == null || code.isEmpty) {
      return;
    }

    try {
      await _studentAcademicService.requestJoinCourse(code);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent to the course owner.'),
          backgroundColor: AppColors.information,
        ),
      );

      _reload();
    } on StudentAcademicServiceException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Student';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Greeting + Date + Compact Join Action
              _buildHeader(displayName),
              const SizedBox(height: AppSpacing.extraLarge),

              // Section Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Today’s Classes',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
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
              const SizedBox(height: AppSpacing.medium),

              // Today's Class List or Empty State
              FutureBuilder<List<ClassScheduleEntry>>(
                future: _schedulesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.extraLarge),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return _buildErrorState(snapshot.error.toString());
                  }

                  final schedules = snapshot.data ?? const [];
                  final todayClasses = _getTodaySchedules(schedules);

                  if (todayClasses.isEmpty) {
                    return _buildEmptyState();
                  }

                  return Column(
                    children: [
                      for (final entry in todayClasses) ...[
                        _buildClassCard(entry),
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

  Widget _buildHeader(String displayName) {
    final todayFormatted = _formatTodayDate(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        final infoColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $displayName',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    todayFormatted,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

        final joinButton = FilledButton.tonalIcon(
          onPressed: _joinCourse,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Join course'),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoColumn,
              const SizedBox(height: AppSpacing.medium),
              joinButton,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: infoColumn),
            joinButton,
          ],
        );
      },
    );
  }

  Widget _buildClassCard(ClassScheduleEntry entry) {
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
                courseId: entry.courseId,
                courseCode: entry.courseCode,
                courseName: entry.courseName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.regular),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.informationBackground,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.startTime,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Text(
                      'to',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      entry.endTime,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.medium),

              // Class Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppRadius.small,
                            ),
                          ),
                          child: Text(
                            entry.courseCode,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (entry.classType.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSoft,
                              borderRadius: BorderRadius.circular(
                                AppRadius.small,
                              ),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              entry.classType,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.courseName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (entry.room.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.meeting_room_outlined,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.room,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        if (entry.teacherName.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                entry.teacherName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.extraLarge,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.event_available_outlined,
            size: 52,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: AppSpacing.medium),
          Text(
            'No classes scheduled today',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: AppSpacing.small),
          Text(
            'Enjoy your day! You have no classes on your schedule for today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
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
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.medium),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

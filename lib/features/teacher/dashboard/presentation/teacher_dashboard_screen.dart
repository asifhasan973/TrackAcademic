import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  static const _service = TeacherAcademicService();

  late Future<TeacherDashboardOverview> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.loadDashboardOverview();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TeacherDashboardOverview>(
      future: _future,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
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
                              'Welcome back, ${_service.currentTeacherName}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.small),
                            const Text(
                              'Your teaching workspace is connected to Firebase.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: () {
                          setState(_reload);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.large),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Center(child: CircularProgressIndicator())
                  else if (snapshot.hasError)
                    _ErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: () {
                        setState(_reload);
                      },
                    )
                  else
                    _DashboardContent(overview: snapshot.data!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final TeacherDashboardOverview overview;

  const _DashboardContent({required this.overview});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - AppSpacing.regular * 3) / 4
                : constraints.maxWidth >= 560
                ? (constraints.maxWidth - AppSpacing.regular) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: AppSpacing.regular,
              runSpacing: AppSpacing.regular,
              children: [
                _MetricCard(
                  width: width,
                  label: 'Courses',
                  value: overview.courses.length.toString(),
                  icon: Icons.menu_book_rounded,
                ),
                _MetricCard(
                  width: width,
                  label: 'Student enrollments',
                  value: overview.studentEnrollments.toString(),
                  icon: Icons.groups_rounded,
                ),
                _MetricCard(
                  width: width,
                  label: 'Active attendance',
                  value: overview.activeSessions.toString(),
                  icon: Icons.how_to_reg_rounded,
                ),
                _MetricCard(
                  width: width,
                  label: 'Published assessments',
                  value: overview.publishedAssessments.toString(),
                  icon: Icons.analytics_rounded,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.large),
        _SectionCard(
          title: 'Your courses',
          child: overview.courses.isEmpty
              ? const _EmptyMessage(message: 'No courses created yet.')
              : Column(
                  children: [
                    for (final course in overview.courses)
                      ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(course.code),
                        subtitle: Text(course.name),
                        trailing: Text(course.room ?? ''),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.large),
        _SectionCard(
          title: 'Weekly schedule',
          child: overview.schedules.isEmpty
              ? const _EmptyMessage(message: 'No classes scheduled yet.')
              : Column(
                  children: [
                    for (final entry in overview.schedules)
                      ListTile(
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: Text(
                          '${entry.day} · ${entry.startTime}-${entry.endTime}',
                        ),
                        subtitle: Text('${entry.courseCode} · ${entry.room}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.regular),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 34, color: AppColors.primary),
            const SizedBox(width: AppSpacing.medium),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.regular),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final String message;

  const _EmptyMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 42),
          const SizedBox(height: AppSpacing.medium),
          Text(message),
          const SizedBox(height: AppSpacing.medium),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

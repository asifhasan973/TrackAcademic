import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/student/courses/presentation/student_course_detail_screen.dart';

class StudentMarksScreen extends StatefulWidget {
  final String? highlightAssessmentId;

  const StudentMarksScreen({this.highlightAssessmentId, super.key});

  @override
  State<StudentMarksScreen> createState() => _StudentMarksScreenState();
}

class _StudentMarksScreenState extends State<StudentMarksScreen> {
  static const _service = AcademicService();

  late Future<List<StudentMarkRecord>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(StudentMarksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightAssessmentId != widget.highlightAssessmentId) {
      setState(_reload);
    }
  }

  void _reload() {
    _future = _service.loadPublishedMarks();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StudentMarkRecord>>(
      future: _future,
      builder: (context, snapshot) {
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Marks',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: AppSpacing.small),
                            Text(
                              'Published assessment results grouped by course. Tap a course to view details.',
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
                  if (snapshot.connectionState != ConnectionState.done &&
                      !snapshot.hasData)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.extraLarge),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (snapshot.hasError)
                    _ErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: () {
                        setState(_reload);
                      },
                    )
                  else
                    _buildMarksContent(snapshot.data ?? const []),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarksContent(List<StudentMarkRecord> marks) {
    if (marks.isEmpty) {
      return const _EmptyCard();
    }

    final grouped = <String, List<StudentMarkRecord>>{};
    for (final mark in marks) {
      grouped.putIfAbsent(mark.courseId, () => []).add(mark);
    }

    double totalEarned = 0;
    double totalPossible = 0;
    for (final mark in marks) {
      totalEarned += mark.score;
      totalPossible += mark.maxScore;
    }
    final overallPercentage = totalPossible <= 0
        ? 0.0
        : (totalEarned / totalPossible) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top summary metrics
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 650
                ? (constraints.maxWidth - AppSpacing.regular) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: AppSpacing.regular,
              runSpacing: AppSpacing.regular,
              children: [
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: 'Published assessments',
                    value: marks.length.toString(),
                    icon: Icons.assignment_turned_in_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: 'Overall published score',
                    value: '${overallPercentage.toStringAsFixed(1)}%',
                    icon: Icons.analytics_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.extraLarge),

        const Text(
          'Courses',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.medium),

        for (final entry in grouped.entries) ...[
          _CourseGroupCard(
            courseId: entry.key,
            marks: entry.value,
            highlightAssessmentId: widget.highlightAssessmentId,
          ),
          const SizedBox(height: AppSpacing.regular),
        ],
      ],
    );
  }
}

class _CourseGroupCard extends StatelessWidget {
  final String courseId;
  final List<StudentMarkRecord> marks;
  final String? highlightAssessmentId;

  const _CourseGroupCard({
    required this.courseId,
    required this.marks,
    this.highlightAssessmentId,
  });

  @override
  Widget build(BuildContext context) {
    final first = marks.first;

    double earned = 0;
    double possible = 0;
    for (final m in marks) {
      earned += m.score;
      possible += m.maxScore;
    }
    final percentage = possible <= 0 ? 0.0 : (earned / possible) * 100;

    final containsHighlighted =
        highlightAssessmentId != null &&
        marks.any((m) => m.assessmentId == highlightAssessmentId);

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(
          color: containsHighlighted ? AppColors.primary : AppColors.border,
          width: containsHighlighted ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.large),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => StudentCourseDetailScreen(
                courseId: courseId,
                courseCode: first.courseCode,
                courseName: first.courseName,
                initialTabIndex: 1, // Focus Marks tab
                highlightAssessmentId: highlightAssessmentId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.informationBackground,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.primary,
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
                          first.courseCode,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (containsHighlighted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'UPDATED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      first.courseName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${marks.length} assessment${marks.length == 1 ? '' : 's'} · ${earned.toStringAsFixed(1)} / ${possible.toStringAsFixed(1)} points',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
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
                  '${percentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.small),
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
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.informationBackground,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(icon, color: AppColors.primary),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

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
      child: const Column(
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: AppSpacing.medium),
          Text(
            'No marks have been published for your enrolled courses yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
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

import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentMarksScreen extends StatefulWidget {
  const StudentMarksScreen({super.key});

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
              constraints: const BoxConstraints(maxWidth: 1050),
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
                              'Published assessment results from your courses.',
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
                    _buildMarks(snapshot.data ?? const []),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarks(List<StudentMarkRecord> marks) {
    if (marks.isEmpty) {
      return const _EmptyCard();
    }

    final grouped = <String, List<StudentMarkRecord>>{};

    for (final mark in marks) {
      grouped.putIfAbsent(mark.courseId, () => []).add(mark);
    }

    double earned = 0;
    double possible = 0;

    for (final mark in marks) {
      earned += mark.score;
      possible += mark.maxScore;
    }

    final overallPercentage = possible <= 0 ? 0.0 : (earned / possible) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        for (final entry in grouped.entries) ...[
          _CourseMarksCard(marks: entry.value),
          const SizedBox(height: AppSpacing.regular),
        ],
      ],
    );
  }
}

class _CourseMarksCard extends StatelessWidget {
  final List<StudentMarkRecord> marks;

  const _CourseMarksCard({required this.marks});

  @override
  Widget build(BuildContext context) {
    final first = marks.first;

    final ordered = [...marks]
      ..sort(
        (a, b) => a.assessmentName.toLowerCase().compareTo(
          b.assessmentName.toLowerCase(),
        ),
      );

    double earned = 0;
    double possible = 0;

    for (final mark in ordered) {
      earned += mark.score;
      possible += mark.maxScore;
    }

    final percentage = possible <= 0 ? 0.0 : (earned / possible) * 100;

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
                    Text(
                      first.courseCode,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      first.courseName,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.large),
          for (int index = 0; index < ordered.length; index++) ...[
            _AssessmentRow(mark: ordered[index]),
            if (index < ordered.length - 1) const Divider(height: 28),
          ],
        ],
      ),
    );
  }
}

class _AssessmentRow extends StatelessWidget {
  final StudentMarkRecord mark;

  const _AssessmentRow({required this.mark});

  @override
  Widget build(BuildContext context) {
    final percentage = mark.maxScore <= 0
        ? 0.0
        : (mark.score / mark.maxScore) * 100;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mark.assessmentName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.extraSmall),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${_format(mark.score)} / ${_format(mark.maxScore)}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(1);
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
            width: 48,
            height: 48,
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
            Icons.assignment_outlined,
            size: 50,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: AppSpacing.medium),
          Text(
            'No published marks yet.',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: AppSpacing.small),
          Text(
            'Marks will appear here after a course owner publishes an assessment.',
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
            size: 42,
            color: AppColors.danger,
          ),
          const SizedBox(height: AppSpacing.medium),
          Text(message, textAlign: TextAlign.center),
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

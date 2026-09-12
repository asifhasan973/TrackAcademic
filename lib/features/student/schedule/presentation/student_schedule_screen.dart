import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/schedule/presentation/widgets/timetable_calendar.dart';

class StudentScheduleScreen extends StatefulWidget {
  const StudentScheduleScreen({super.key});

  @override
  State<StudentScheduleScreen> createState() => _StudentScheduleScreenState();
}

class _StudentScheduleScreenState extends State<StudentScheduleScreen> {
  static const _service = AcademicService();

  late Future<List<ClassScheduleEntry>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.loadCurrentSchedules();
  }

  TimetableEntry _toTimetableEntry(ClassScheduleEntry s) {
    return TimetableEntry(
      id: s.id,
      courseId: s.courseId,
      courseCode: s.courseCode,
      courseName: s.courseName,
      teacherName: s.teacherName,
      dayIndex: s.dayIndex,
      day: s.day,
      startTime: s.startTime,
      endTime: s.endTime,
      room: s.room,
      classType: s.classType,
      status: s.status,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClassScheduleEntry>>(
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
                              'Class Schedule',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: AppSpacing.small),
                            Text(
                              'Your weekly class timetable across enrolled courses.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
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
                    TimetableCalendar(
                      entries: (snapshot.data ?? const [])
                          .map(_toTimetableEntry)
                          .toList(),
                      isTeacher: false,
                      onRefresh: () => setState(_reload),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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

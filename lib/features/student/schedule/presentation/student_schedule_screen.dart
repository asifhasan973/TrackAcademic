import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentScheduleScreen extends StatefulWidget {
  const StudentScheduleScreen({super.key});

  @override
  State<StudentScheduleScreen> createState() => _StudentScheduleScreenState();
}

class _StudentScheduleScreenState extends State<StudentScheduleScreen> {
  static const _service = AcademicService();

  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  late Future<List<ClassScheduleEntry>> _future;

  bool _showWeekView = false;
  int _selectedDay = DateTime.now().weekday % 7;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.loadCurrentSchedules();
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
                              'Your current Firebase-backed course schedule.',
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
                    _buildContent(snapshot.data ?? const []),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(List<ClassScheduleEntry> schedules) {
    final ordered = [...schedules]
      ..sort((a, b) {
        final dayComparison = a.dayIndex.compareTo(b.dayIndex);

        if (dayComparison != 0) {
          return dayComparison;
        }

        return a.startTime.compareTo(b.startTime);
      });

    final todayIndex = DateTime.now().weekday % 7;

    final todayCount = ordered.where((item) {
      return item.dayIndex == todayIndex;
    }).length;

    final changedCount = ordered.where((item) {
      final status = item.status.toLowerCase();

      return status != 'scheduled' && status != 'active';
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final double width;

            if (constraints.maxWidth >= 800) {
              width = (constraints.maxWidth - AppSpacing.regular * 2) / 3;
            } else if (constraints.maxWidth >= 520) {
              width = (constraints.maxWidth - AppSpacing.regular) / 2;
            } else {
              width = constraints.maxWidth;
            }

            return Wrap(
              spacing: AppSpacing.regular,
              runSpacing: AppSpacing.regular,
              children: [
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: 'Weekly classes',
                    value: ordered.length.toString(),
                    icon: Icons.calendar_month_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: 'Classes today',
                    value: todayCount.toString(),
                    icon: Icons.today_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _SummaryCard(
                    label: 'Schedule changes',
                    value: changedCount.toString(),
                    icon: Icons.update_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.large),
        _buildControls(),
        const SizedBox(height: AppSpacing.large),
        _buildScheduleList(ordered),
      ],
    );
  }

  Widget _buildControls() {
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
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.view_day_outlined),
                label: Text('Day'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.view_week_outlined),
                label: Text('Week'),
              ),
            ],
            selected: {_showWeekView},
            onSelectionChanged: (selection) {
              setState(() {
                _showWeekView = selection.first;
              });
            },
          ),
          if (!_showWeekView) ...[
            const SizedBox(height: AppSpacing.regular),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int index = 0; index < _days.length; index++) ...[
                    ChoiceChip(
                      selected: _selectedDay == index,
                      label: Text(_days[index]),
                      onSelected: (_) {
                        setState(() {
                          _selectedDay = index;
                        });
                      },
                    ),
                    if (index < _days.length - 1)
                      const SizedBox(width: AppSpacing.small),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleList(List<ClassScheduleEntry> schedules) {
    final visible = _showWeekView
        ? schedules
        : schedules.where((item) {
            return item.dayIndex == _selectedDay;
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
          Text(
            _showWeekView ? 'Weekly schedule' : _days[_selectedDay],
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.regular),
          if (visible.isEmpty)
            const _EmptySchedule()
          else
            for (int index = 0; index < visible.length; index++) ...[
              if (_showWeekView &&
                  (index == 0 ||
                      visible[index].dayIndex != visible[index - 1].dayIndex))
                Padding(
                  padding: EdgeInsets.only(
                    top: index == 0 ? 0 : AppSpacing.large,
                    bottom: AppSpacing.small,
                  ),
                  child: Text(
                    _dayLabel(visible[index]),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              _ScheduleCard(schedule: visible[index]),
              if (index < visible.length - 1)
                const SizedBox(height: AppSpacing.medium),
            ],
        ],
      ),
    );
  }

  String _dayLabel(ClassScheduleEntry schedule) {
    if (schedule.day.trim().isNotEmpty) {
      return schedule.day;
    }

    if (schedule.dayIndex >= 0 && schedule.dayIndex < _days.length) {
      return _days[schedule.dayIndex];
    }

    return 'Scheduled class';
  }
}

class _ScheduleCard extends StatelessWidget {
  final ClassScheduleEntry schedule;

  const _ScheduleCard({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (schedule.classType.trim().isNotEmpty) schedule.classType,
      if (schedule.room.trim().isNotEmpty) schedule.room,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.regular),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.small,
              vertical: AppSpacing.medium,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Column(
              children: [
                Text(
                  schedule.startTime.isEmpty ? '--' : schedule.startTime,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppSpacing.extraSmall),
                Text(
                  schedule.endTime.isEmpty ? '--' : schedule.endTime,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.regular),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${schedule.courseCode} · ${schedule.courseName}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    details.join(' · '),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                if (schedule.teacherName.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.extraSmall),
                  Text(
                    schedule.teacherName,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (schedule.status.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.medium),
                  _StatusLabel(status: schedule.status),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String status;

  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.medium,
        vertical: AppSpacing.extraSmall,
      ),
      decoration: BoxDecoration(
        color: AppColors.informationBackground,
        borderRadius: BorderRadius.circular(AppRadius.circular),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
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

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.extraLarge),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.event_available_rounded,
            color: AppColors.textTertiary,
            size: 48,
          ),
          SizedBox(height: AppSpacing.medium),
          Text(
            'No classes scheduled.',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
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

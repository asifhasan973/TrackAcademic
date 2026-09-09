import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherScheduleScreen extends StatefulWidget {
  const TeacherScheduleScreen({super.key});

  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
  static const _service = TeacherAcademicService();

  late Future<_SchedulePageData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_SchedulePageData> _load() async {
    return _SchedulePageData(
      courses: await _service.loadMyCourses(),
      schedules: await _service.loadMySchedules(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SchedulePageData>(
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Create and manage your class schedule.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (snapshot.hasData)
                        FilledButton.icon(
                          onPressed: snapshot.data!.courses.isEmpty
                              ? null
                              : () => _openEditor(snapshot.data!.courses),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add class'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.large),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Center(child: CircularProgressIndicator())
                  else if (snapshot.hasError)
                    Text(snapshot.error.toString())
                  else if (snapshot.data!.schedules.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.extraLarge),
                        child: Text('No classes scheduled yet.'),
                      ),
                    )
                  else
                    for (final schedule in snapshot.data!.schedules) ...[
                      _ScheduleCard(
                        schedule: schedule,
                        onEdit: () => _openEditor(
                          snapshot.data!.courses,
                          existing: schedule,
                        ),
                        onDelete: () => _delete(schedule),
                      ),
                      const SizedBox(height: AppSpacing.regular),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditor(
    List<TeacherCourse> courses, {
    TeacherScheduleEntry? existing,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _ScheduleEditorDialog(courses: courses, existing: existing),
    );

    if (changed == true) {
      setState(_reload);
    }
  }

  Future<void> _delete(TeacherScheduleEntry schedule) async {
    try {
      await _service.deleteSchedule(schedule.id);

      if (mounted) {
        setState(_reload);
      }
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _ScheduleEditorDialog extends StatefulWidget {
  final List<TeacherCourse> courses;
  final TeacherScheduleEntry? existing;

  const _ScheduleEditorDialog({required this.courses, this.existing});

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  static const _service = TeacherAcademicService();

  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  late String _courseId;
  late int _dayIndex;
  late String _classType;

  late final TextEditingController _startController;

  late final TextEditingController _endController;

  late final TextEditingController _roomController;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _courseId = existing?.courseId ?? widget.courses.first.id;

    _dayIndex = existing?.dayIndex ?? 0;

    _classType = existing?.classType ?? 'Theory';

    _startController = TextEditingController(
      text: existing?.startTime ?? '09:00',
    );

    _endController = TextEditingController(text: existing?.endTime ?? '09:50');

    _roomController = TextEditingController(text: existing?.room ?? '');
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add class' : 'Edit class'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _courseId,
              decoration: const InputDecoration(labelText: 'Course'),
              items: widget.courses
                  .map(
                    (course) => DropdownMenuItem(
                      value: course.id,
                      child: Text('${course.code} · ${course.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _courseId = value;
                }
              },
            ),
            const SizedBox(height: AppSpacing.medium),
            DropdownButtonFormField<int>(
              initialValue: _dayIndex,
              decoration: const InputDecoration(labelText: 'Day'),
              items: List.generate(
                _days.length,
                (index) =>
                    DropdownMenuItem(value: index, child: Text(_days[index])),
              ),
              onChanged: (value) {
                if (value != null) {
                  _dayIndex = value;
                }
              },
            ),
            const SizedBox(height: AppSpacing.medium),
            TextField(
              controller: _startController,
              decoration: const InputDecoration(
                labelText: 'Start time (HH:MM)',
              ),
            ),
            const SizedBox(height: AppSpacing.medium),
            TextField(
              controller: _endController,
              decoration: const InputDecoration(labelText: 'End time (HH:MM)'),
            ),
            const SizedBox(height: AppSpacing.medium),
            TextField(
              controller: _roomController,
              decoration: const InputDecoration(labelText: 'Room'),
            ),
            const SizedBox(height: AppSpacing.medium),
            DropdownButtonFormField<String>(
              initialValue: _classType,
              decoration: const InputDecoration(labelText: 'Class type'),
              items: const [
                DropdownMenuItem(value: 'Theory', child: Text('Theory')),
                DropdownMenuItem(value: 'Practical', child: Text('Practical')),
                DropdownMenuItem(value: 'Makeup', child: Text('Makeup')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _classType = value;
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
    });

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _service.createSchedule(
          courseId: _courseId,
          dayIndex: _dayIndex,
          day: _days[_dayIndex],
          startTime: _startController.text.trim(),
          endTime: _endController.text.trim(),
          room: _roomController.text.trim(),
          classType: _classType,
        );
      } else {
        await _service.updateSchedule(
          scheduleId: existing.id,
          courseId: _courseId,
          dayIndex: _dayIndex,
          day: _days[_dayIndex],
          startTime: _startController.text.trim(),
          endTime: _endController.text.trim(),
          room: _roomController.text.trim(),
          classType: _classType,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on TeacherAcademicServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _ScheduleCard extends StatelessWidget {
  final TeacherScheduleEntry schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: const Icon(Icons.calendar_month_rounded),
        title: Text(
          '${schedule.day} · ${schedule.startTime}-${schedule.endTime}',
        ),
        subtitle: Text(
          '${schedule.courseCode} · ${schedule.courseName}\n${schedule.classType} · ${schedule.room}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchedulePageData {
  final List<TeacherCourse> courses;
  final List<TeacherScheduleEntry> schedules;

  const _SchedulePageData({required this.courses, required this.schedules});
}

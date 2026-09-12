import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/schedule/presentation/widgets/timetable_calendar.dart';

class TeacherScheduleScreen extends StatefulWidget {
  final String? initialCourseId;

  const TeacherScheduleScreen({this.initialCourseId, super.key});

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

  TimetableEntry _toTimetableEntry(TeacherScheduleEntry s) {
    return TimetableEntry(
      id: s.id,
      courseId: s.courseId,
      courseCode: s.courseCode,
      courseName: s.courseName,
      teacherName: _service.currentTeacherName,
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
                              'Create and manage your class schedule timetable.',
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
                  else
                    TimetableCalendar(
                      entries: snapshot.data!.schedules
                          .map(_toTimetableEntry)
                          .toList(),
                      isTeacher: true,
                      initialCourseId: widget.initialCourseId,
                      onAddTiming: snapshot.data!.courses.isEmpty
                          ? null
                          : () => _openEditor(snapshot.data!.courses),
                      onEditTiming: (entry) {
                        final existing = snapshot.data!.schedules.firstWhere(
                          (s) => s.id == entry.id,
                        );
                        _openEditor(snapshot.data!.courses, existing: existing);
                      },
                      onDeleteTiming: (entry) {
                        final existing = snapshot.data!.schedules.firstWhere(
                          (s) => s.id == entry.id,
                        );
                        _delete(existing);
                      },
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

  Future<void> _openEditor(
    List<TeacherCourse> courses, {
    TeacherScheduleEntry? existing,
    String? defaultCourseId,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ScheduleEditorDialog(
        courses: courses,
        existing: existing,
        defaultCourseId: defaultCourseId ?? widget.initialCourseId,
      ),
    );

    if (changed == true) {
      setState(_reload);
    }
  }

  Future<void> _delete(TeacherScheduleEntry schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete scheduled class?'),
        content: Text(
          'Delete ${schedule.courseCode} on ${schedule.day} (${schedule.startTime} - ${schedule.endTime})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

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
  final String? defaultCourseId;

  const _ScheduleEditorDialog({
    required this.courses,
    this.existing,
    this.defaultCourseId,
  });

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

  final _formKey = GlobalKey<FormState>();

  late String _courseId;
  late int _dayIndex;
  late String _classType;

  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _roomController;

  bool _submitting = false;
  bool _userModifiedRoom = false;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _courseId =
        existing?.courseId ??
        (widget.defaultCourseId != null &&
                widget.courses.any((c) => c.id == widget.defaultCourseId)
            ? widget.defaultCourseId!
            : widget.courses.first.id);

    final initialCourse = widget.courses.firstWhere(
      (c) => c.id == _courseId,
      orElse: () => widget.courses.first,
    );

    _dayIndex = existing?.dayIndex ?? 0;

    _classType = existing?.classType ?? 'Theory';

    _startController = TextEditingController(
      text: existing?.startTime ?? '09:00',
    );

    _endController = TextEditingController(text: existing?.endTime ?? '09:50');

    _roomController = TextEditingController(
      text: existing?.room ?? (initialCourse.room ?? ''),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  int? _parseTimeMinutes(String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final min = int.tryParse(match.group(2)!);
    if (hour == null ||
        min == null ||
        hour < 0 ||
        hour > 23 ||
        min < 0 ||
        min > 59) {
      return null;
    }
    return hour * 60 + min;
  }

  String _formatTime(String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (match == null) return text.trim();
    final hour = int.parse(match.group(1)!);
    final min = int.parse(match.group(2)!);
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add class' : 'Edit class'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                  validator: (val) => val == null || val.isEmpty
                      ? 'Please select a course'
                      : null,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _courseId = value;
                        if (widget.existing == null && !_userModifiedRoom) {
                          final selected = widget.courses.firstWhere(
                            (c) => c.id == value,
                            orElse: () => widget.courses.first,
                          );
                          if (selected.room != null &&
                              selected.room!.isNotEmpty) {
                            _roomController.text = selected.room!;
                          }
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                DropdownButtonFormField<int>(
                  initialValue: _dayIndex,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: List.generate(
                    _days.length,
                    (index) => DropdownMenuItem(
                      value: index,
                      child: Text(_days[index]),
                    ),
                  ),
                  validator: (val) =>
                      val == null ? 'Please select a day' : null,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _dayIndex = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _startController,
                  decoration: const InputDecoration(
                    labelText: 'Start time (HH:MM)',
                    hintText: '09:00',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Start time is required';
                    }
                    if (_parseTimeMinutes(val) == null) {
                      return 'Enter valid time in HH:mm format (e.g. 09:00)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _endController,
                  decoration: const InputDecoration(
                    labelText: 'End time (HH:MM)',
                    hintText: '09:50',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'End time is required';
                    }
                    final endMin = _parseTimeMinutes(val);
                    if (endMin == null) {
                      return 'Enter valid time in HH:mm format (e.g. 09:50)';
                    }
                    final startMin = _parseTimeMinutes(_startController.text);
                    if (startMin != null && endMin <= startMin) {
                      return 'End time must be after start time';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: 'Room'),
                  onChanged: (val) {
                    _userModifiedRoom = true;
                  },
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Room is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                DropdownButtonFormField<String>(
                  initialValue: _classType,
                  decoration: const InputDecoration(labelText: 'Class type'),
                  items: const [
                    DropdownMenuItem(value: 'Theory', child: Text('Theory')),
                    DropdownMenuItem(
                      value: 'Practical',
                      child: Text('Practical'),
                    ),
                    DropdownMenuItem(value: 'Makeup', child: Text('Makeup')),
                  ],
                  validator: (val) => val == null || val.isEmpty
                      ? 'Please select class type'
                      : null,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _classType = value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final existing = widget.existing;
      final startTime = _formatTime(_startController.text);
      final endTime = _formatTime(_endController.text);
      final room = _roomController.text.trim();

      if (existing == null) {
        await _service.createSchedule(
          courseId: _courseId,
          dayIndex: _dayIndex,
          day: _days[_dayIndex],
          startTime: startTime,
          endTime: endTime,
          room: room,
          classType: _classType,
        );
      } else {
        await _service.updateSchedule(
          scheduleId: existing.id,
          courseId: _courseId,
          dayIndex: _dayIndex,
          day: _days[_dayIndex],
          startTime: startTime,
          endTime: endTime,
          room: room,
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

class _SchedulePageData {
  final List<TeacherCourse> courses;
  final List<TeacherScheduleEntry> schedules;

  const _SchedulePageData({required this.courses, required this.schedules});
}

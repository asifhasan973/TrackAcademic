import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherCreateAttendanceScreen extends StatefulWidget {
  final bool showBackButton;

  const TeacherCreateAttendanceScreen({this.showBackButton = false, super.key});

  @override
  State<TeacherCreateAttendanceScreen> createState() =>
      _TeacherCreateAttendanceScreenState();
}

class _TeacherCreateAttendanceScreenState
    extends State<TeacherCreateAttendanceScreen> {
  static const _service = TeacherAcademicService();

  late Future<_AttendancePageData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_AttendancePageData> _load() async {
    final courses = await _service.loadMyCourses();
    final sessions = await _service.loadAttendanceSessions();

    return _AttendancePageData(courses: courses, sessions: sessions);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AttendancePageData>(
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
                      if (widget.showBackButton)
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attendance',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Create and monitor real attendance sessions.',
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
                    Text(snapshot.error.toString())
                  else
                    _buildContent(snapshot.data!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(_AttendancePageData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: data.courses.isEmpty
              ? null
              : () async {
                  final created = await showDialog<bool>(
                    context: context,
                    builder: (context) =>
                        _CreateSessionDialog(courses: data.courses),
                  );

                  if (created == true) {
                    setState(_reload);
                  }
                },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create attendance session'),
        ),
        if (data.courses.isEmpty) ...[
          const SizedBox(height: AppSpacing.medium),
          const Text(
            'Create a course before starting attendance.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.large),
        if (data.sessions.isEmpty)
          const _EmptyAttendance()
        else
          for (final session in data.sessions) ...[
            _SessionCard(
              session: session,
              onView: () => _showSession(session),
              onClose: session.status == 'active'
                  ? () => _closeSession(session)
                  : null,
            ),
            const SizedBox(height: AppSpacing.regular),
          ],
      ],
    );
  }

  Future<void> _showSession(TeacherAttendanceSession session) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AttendanceMonitorDialog(session: session),
    );
  }

  Future<void> _closeSession(TeacherAttendanceSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close attendance?'),
        content: const Text(
          'Students who have not submitted attendance will be recorded as absent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.closeAttendanceSession(session.id);

      if (!mounted) {
        return;
      }

      setState(_reload);
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

class _CreateSessionDialog extends StatefulWidget {
  final List<TeacherCourse> courses;

  const _CreateSessionDialog({required this.courses});

  @override
  State<_CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<_CreateSessionDialog> {
  static const _service = TeacherAcademicService();

  late String _courseId;

  final _durationController = TextEditingController(text: '15');

  final _passcodeController = TextEditingController();

  final _radiusController = TextEditingController(text: '100');

  String _classType = 'Theory';

  bool _requiresPasscode = true;
  bool _requiresGps = false;
  bool _allowLateEntry = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    _courseId = widget.courses.first.id;
    _generatePasscode();
  }

  void _generatePasscode() {
    final value = 100000 + Random.secure().nextInt(900000);

    _passcodeController.text = value.toString();
  }

  @override
  void dispose() {
    _durationController.dispose();
    _passcodeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create attendance session'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
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
                    setState(() {
                      _courseId = value;
                    });
                  }
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
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _classType = value;
                    });
                  }
                },
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes)',
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require passcode'),
                value: _requiresPasscode,
                onChanged: (value) {
                  setState(() {
                    _requiresPasscode = value;
                  });
                },
              ),
              if (_requiresPasscode)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _passcodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Passcode',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Generate passcode',
                      onPressed: _generatePasscode,
                      icon: const Icon(Icons.autorenew_rounded),
                    ),
                  ],
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require GPS verification'),
                subtitle: const Text(
                  'Your current device location will be used as the attendance center.',
                ),
                value: _requiresGps,
                onChanged: (value) {
                  setState(() {
                    _requiresGps = value;
                  });
                },
              ),
              if (_requiresGps) ...[
                const SizedBox(height: AppSpacing.small),
                TextField(
                  controller: _radiusController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Allowed radius (meters)',
                    helperText:
                        'Students must be within this distance from your current location.',
                  ),
                ),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow late entry'),
                value: _allowLateEntry,
                onChanged: (value) {
                  setState(() {
                    _allowLateEntry = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<Position> _getTeacherPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw const TeacherAcademicServiceException(
        'Location services are disabled on this device.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const TeacherAcademicServiceException(
        'Location permission is required for GPS attendance.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const TeacherAcademicServiceException(
        'Location permission is blocked. Allow location access in your browser or device settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _submit() async {
    final duration = int.tryParse(_durationController.text.trim());

    if (duration == null || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid attendance duration.')),
      );

      return;
    }

    final radius = _requiresGps
        ? double.tryParse(_radiusController.text.trim())
        : null;

    if (_requiresGps && (radius == null || radius <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid GPS radius.')),
      );

      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      Position? position;

      if (_requiresGps) {
        position = await _getTeacherPosition();
      }

      await _service.createAttendanceSession(
        courseId: _courseId,
        classType: _classType,
        durationMinutes: duration,
        requiresPasscode: _requiresPasscode,
        passcode: _requiresPasscode ? _passcodeController.text.trim() : null,
        requiresGps: _requiresGps,
        latitude: position?.latitude,
        longitude: position?.longitude,
        radiusMeters: radius,
        allowLateEntry: _allowLateEntry,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get your current location: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _AttendanceMonitorDialog extends StatefulWidget {
  final TeacherAttendanceSession session;

  const _AttendanceMonitorDialog({required this.session});

  @override
  State<_AttendanceMonitorDialog> createState() =>
      _AttendanceMonitorDialogState();
}

class _AttendanceMonitorDialogState extends State<_AttendanceMonitorDialog> {
  static const _service = TeacherAcademicService();

  late Future<_MonitorData> _future;

  Timer? _timer;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();

    _reload();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      _ticks++;

      if (_ticks % 3 == 0) {
        _reload();
      } else {
        setState(() {});
      }
    });
  }

  void _reload() {
    _future = _load();

    if (mounted) {
      setState(() {});
    }
  }

  Future<_MonitorData> _load() async {
    final results = await Future.wait([
      _service.loadCourseStudents(widget.session.courseId),
      _service.loadAttendanceRecords(widget.session),
    ]);

    return _MonitorData(
      students: results[0] as List<EnrolledStudent>,
      records: results[1] as List<TeacherAttendanceRecord>,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _remaining {
    final endsAt = widget.session.endsAt;

    if (endsAt == null) {
      return '--:--';
    }

    final duration = endsAt.difference(DateTime.now());

    if (duration.isNegative) {
      return '00:00';
    }

    final minutes = duration.inMinutes;

    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.session.courseCode} attendance'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: FutureBuilder<_MonitorData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;

            final students = data?.students ?? const <EnrolledStudent>[];

            final records = {
              for (final record
                  in data?.records ?? const <TeacherAttendanceRecord>[])
                record.studentId: record,
            };

            int present = 0;
            int late = 0;
            int absent = 0;
            int waiting = 0;

            for (final student in students) {
              final status = records[student.uid]?.status ?? 'waiting';

              switch (status) {
                case 'present':
                  present++;
                  break;
                case 'late':
                  late++;
                  break;
                case 'absent':
                  absent++;
                  break;
                default:
                  waiting++;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.regular),
                  decoration: BoxDecoration(
                    color: AppColors.informationBackground,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 12,
                    children: [
                      _MonitorStat(label: 'Time remaining', value: _remaining),
                      _MonitorStat(
                        label: 'Enrolled',
                        value: students.length.toString(),
                      ),
                      _MonitorStat(label: 'Present', value: present.toString()),
                      _MonitorStat(label: 'Late', value: late.toString()),
                      _MonitorStat(label: 'Waiting', value: waiting.toString()),
                      _MonitorStat(label: 'Absent', value: absent.toString()),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.regular),
                Expanded(
                  child:
                      snapshot.connectionState != ConnectionState.done &&
                          data == null
                      ? const Center(child: CircularProgressIndicator())
                      : students.isEmpty
                      ? const Center(child: Text('No students enrolled.'))
                      : ListView.separated(
                          itemCount: students.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (context, index) {
                            final student = students[index];

                            final status =
                                records[student.uid]?.status ?? 'waiting';

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  student.displayName.isEmpty
                                      ? '?'
                                      : student.displayName[0].toUpperCase(),
                                ),
                              ),
                              title: Text(student.displayName),
                              subtitle: Text(
                                '${student.institutionId}\n${student.email}',
                              ),
                              isThreeLine: true,
                              trailing: DropdownButton<String>(
                                value: status,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'waiting',
                                    child: Text('Waiting'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'present',
                                    child: Text('Present'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'late',
                                    child: Text('Late'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'absent',
                                    child: Text('Absent'),
                                  ),
                                ],
                                onChanged: widget.session.status == 'active'
                                    ? (value) {
                                        if (value != null) {
                                          _setStatus(student, value);
                                        }
                                      }
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _setStatus(EnrolledStudent student, String status) async {
    try {
      await _service.setAttendanceStatus(
        sessionId: widget.session.id,
        studentId: student.uid,
        status: status,
      );

      _reload();
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

class _MonitorStat extends StatelessWidget {
  final String label;
  final String value;

  const _MonitorStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 105,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
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
    );
  }
}

class _MonitorData {
  final List<EnrolledStudent> students;
  final List<TeacherAttendanceRecord> records;

  const _MonitorData({required this.students, required this.records});
}

class _SessionCard extends StatelessWidget {
  final TeacherAttendanceSession session;
  final VoidCallback onView;
  final VoidCallback? onClose;

  const _SessionCard({
    required this.session,
    required this.onView,
    required this.onClose,
  });

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
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session.courseCode} · ${session.courseName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${session.classType} · ${session.durationMinutes} min · ${session.status}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (session.requiresGps)
                    const Text(
                      'GPS verification enabled',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            OutlinedButton(onPressed: onView, child: const Text('Monitor')),
            if (onClose != null) ...[
              const SizedBox(width: AppSpacing.small),
              FilledButton(
                onPressed: onClose,
                child: const Text('Close session'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyAttendance extends StatelessWidget {
  const _EmptyAttendance();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.extraLarge),
        child: Text(
          'No attendance sessions have been created.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _AttendancePageData {
  final List<TeacherCourse> courses;
  final List<TeacherAttendanceSession> sessions;

  const _AttendancePageData({required this.courses, required this.sessions});
}

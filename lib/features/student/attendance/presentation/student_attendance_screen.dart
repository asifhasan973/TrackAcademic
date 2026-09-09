import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  static const _service = StudentAcademicService();

  late Future<_AttendanceData> _future;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _reload() {
    _future = _load();
  }

  Future<_AttendanceData> _load() async {
    final results = await Future.wait([
      _service.loadActiveSessions(),
      _service.loadMyAttendanceRecords(),
    ]);

    return _AttendanceData(
      sessions: results[0] as List<StudentAttendanceSession>,
      records: results[1] as List<StudentAttendanceRecord>,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AttendanceData>(
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
                        child: Text(
                          'Attendance',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(_reload);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const Text(
                    'Mark attendance for your enrolled courses.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.large),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Center(child: CircularProgressIndicator())
                  else if (snapshot.hasError)
                    Text(snapshot.error.toString())
                  else
                    _content(snapshot.data!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(_AttendanceData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active sessions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.medium),
        if (data.sessions.isEmpty)
          const Text(
            'No active attendance session is available.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final session in data.sessions) ...[
            _SessionCard(session: session, onSubmit: () => _submit(session)),
            const SizedBox(height: AppSpacing.regular),
          ],
        const SizedBox(height: AppSpacing.extraLarge),
        const Text(
          'Attendance history',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.medium),
        if (data.records.isEmpty)
          const Text(
            'No attendance records yet.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final record in data.records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                record.status == 'present'
                    ? Icons.check_circle_rounded
                    : record.status == 'late'
                    ? Icons.schedule_rounded
                    : Icons.cancel_rounded,
              ),
              title: Text('${record.courseCode} · ${record.courseName}'),
              subtitle: Text(
                record.source.isEmpty
                    ? record.status
                    : '${record.status} · ${record.source}',
              ),
            ),
      ],
    );
  }

  Future<void> _submit(StudentAttendanceSession session) async {
    String? passcode;

    if (session.requiresPasscode) {
      final controller = TextEditingController();

      passcode = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Passcode'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Attendance passcode'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      controller.dispose();

      if (passcode == null || passcode.isEmpty) {
        return;
      }
    }

    try {
      await _service.submitAttendance(session: session, passcode: passcode);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attendance submitted.')));

      setState(_reload);
    } on StudentAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _SessionCard extends StatelessWidget {
  final StudentAttendanceSession session;
  final VoidCallback onSubmit;

  const _SessionCard({required this.session, required this.onSubmit});

  String get remaining {
    final endsAt = session.endsAt;

    if (endsAt == null) {
      return '--:--';
    }

    final duration = endsAt.difference(DateTime.now());

    if (duration.isNegative) {
      return session.allowLateEntry ? 'Late entry' : '00:00';
    }

    final minutes = duration.inMinutes;

    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

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
                  const SizedBox(height: 4),
                  Text(
                    session.classType,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Time remaining: $remaining',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (session.requiresGps)
                    const Text(
                      'GPS verification required',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onSubmit,
              child: const Text('Mark attendance'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceData {
  final List<StudentAttendanceSession> sessions;

  final List<StudentAttendanceRecord> records;

  const _AttendanceData({required this.sessions, required this.records});
}

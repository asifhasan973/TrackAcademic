import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final String? highlightSessionId;

  const StudentAttendanceScreen({this.highlightSessionId, super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  static const _service = StudentAcademicService();

  late Stream<List<StudentAttendanceSession>> _sessionsStream;
  late Future<List<StudentAttendanceRecord>> _recordsFuture;

  final Set<String> _submittingSessionIds = <String>{};
  final Set<String> _submittedSessionIds = <String>{};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sessionsStream = _service.streamActiveSessions();
    _recordsFuture = _service.loadMyAttendanceRecords();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _reload() {
    setState(() {
      _sessionsStream = _service.streamActiveSessions();
      _recordsFuture = _service.loadMyAttendanceRecords();
    });
  }

  void _reloadRecords() {
    setState(() {
      _recordsFuture = _service.loadMyAttendanceRecords();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    tooltip: 'Refresh',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const Text(
                'Mark attendance for your enrolled courses.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.large),

              // Active sessions header
              const Text(
                'Active sessions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.medium),

              // Real-time active sessions
              StreamBuilder<List<StudentAttendanceSession>>(
                stream: _sessionsStream,
                builder: (context, sessionSnapshot) {
                  if (sessionSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !sessionSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (sessionSnapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Failed to load active sessions: ${sessionSnapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  final sessions = sessionSnapshot.data ?? const [];

                  if (sessions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No active attendance session is available.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return FutureBuilder<List<StudentAttendanceRecord>>(
                    future: _recordsFuture,
                    builder: (context, recordSnapshot) {
                      final records = recordSnapshot.data ?? const [];

                      return Column(
                        children: [
                          for (final session in sessions) ...[
                            _SessionCard(
                              session: session,
                              isHighlighted:
                                  session.id == widget.highlightSessionId,
                              isAlreadySubmitted:
                                  _submittedSessionIds.contains(session.id) ||
                                  records.any(
                                    (r) =>
                                        r.sessionId == session.id &&
                                        r.status != 'waiting',
                                  ),
                              isSubmitting: _submittingSessionIds.contains(
                                session.id,
                              ),
                              onSubmit: () => _submit(session),
                            ),
                            const SizedBox(height: AppSpacing.regular),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: AppSpacing.extraLarge),

              // Attendance history header
              const Text(
                'Attendance history',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.medium),

              FutureBuilder<List<StudentAttendanceRecord>>(
                future: _recordsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done &&
                      !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text(
                      'Failed to load history: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    );
                  }

                  final records = snapshot.data ?? const [];

                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No attendance records yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final record in records)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            record.status == 'present'
                                ? Icons.check_circle_rounded
                                : record.status == 'late'
                                ? Icons.schedule_rounded
                                : Icons.cancel_rounded,
                            color: record.status == 'present'
                                ? AppColors.success
                                : record.status == 'late'
                                ? AppColors.warning
                                : Colors.red,
                          ),
                          title: Text(
                            '${record.courseCode} · ${record.courseName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            record.source.isEmpty
                                ? record.status
                                : '${record.status} · ${record.source}',
                          ),
                        ),
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

  Future<void> _submit(StudentAttendanceSession session) async {
    if (_submittingSessionIds.contains(session.id)) {
      return;
    }

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

    setState(() {
      _submittingSessionIds.add(session.id);
    });

    try {
      await _service.submitAttendance(session: session, passcode: passcode);

      if (!mounted) {
        return;
      }

      setState(() {
        _submittedSessionIds.add(session.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance submitted successfully.'),
          backgroundColor: AppColors.success,
        ),
      );

      _reloadRecords();
    } on StudentAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingSessionIds.remove(session.id);
        });
      }
    }
  }
}

class _SessionCard extends StatelessWidget {
  final StudentAttendanceSession session;
  final bool isHighlighted;
  final bool isAlreadySubmitted;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _SessionCard({
    required this.session,
    required this.isHighlighted,
    required this.isAlreadySubmitted,
    required this.isSubmitting,
    required this.onSubmit,
  });

  bool get isExpired {
    final endsAt = session.endsAt;
    if (endsAt == null) {
      return false;
    }
    final now = DateTime.now();
    return now.isAfter(endsAt) && !session.allowLateEntry;
  }

  bool get canSubmit {
    return !isExpired && !isAlreadySubmitted && !isSubmitting;
  }

  String get remaining {
    final endsAt = session.endsAt;

    if (endsAt == null) {
      return '--:--';
    }

    final duration = endsAt.difference(DateTime.now());

    if (duration.isNegative) {
      return session.allowLateEntry
          ? 'Late entry accepted'
          : 'Expired (closed)';
    }

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  String get _dateAndTimeString {
    final start = session.startedAt;
    if (start == null) {
      return 'Today';
    }
    final now = DateTime.now();
    final isToday =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final datePart = isToday
        ? 'Today'
        : '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final timePart =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return '$datePart · $timePart';
  }

  @override
  Widget build(BuildContext context) {
    final requirements = <String>[
      if (session.requiresPasscode) 'Passcode',
      if (session.requiresGps) 'GPS verified',
    ];

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(
          color: isHighlighted ? AppColors.primary : AppColors.border,
          width: isHighlighted ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 560;

            final details = Column(
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
                  '$_dateAndTimeString · ${session.classType} (${session.durationMinutes} min)',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: $remaining',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isAlreadySubmitted
                        ? AppColors.success
                        : canSubmit
                        ? AppColors.textPrimary
                        : Colors.red,
                  ),
                ),
                if (requirements.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Requirements: ${requirements.join(", ")}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            );

            final Widget actionButton;
            if (isAlreadySubmitted) {
              actionButton = FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Attendance marked'),
              );
            } else if (isSubmitting) {
              actionButton = const FilledButton(
                onPressed: null,
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            } else if (isExpired) {
              actionButton = const FilledButton(
                onPressed: null,
                child: Text('Session expired'),
              );
            } else {
              actionButton = FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                label: const Text('Mark attendance'),
              );
            }

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: AppSpacing.medium),
                  actionButton,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: details),
                const SizedBox(width: AppSpacing.medium),
                actionButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

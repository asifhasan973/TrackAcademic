import 'package:flutter/material.dart';
import 'package:trackademic/core/services/academic_service.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/services/student_academic_service.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/ui_preview/presentation/role_workspace_screen.dart';

class AccountWorkspaceScreen extends StatefulWidget {
  final AppUserProfile profile;

  const AccountWorkspaceScreen({required this.profile, super.key});

  @override
  State<AccountWorkspaceScreen> createState() => _AccountWorkspaceScreenState();
}

class _AccountWorkspaceScreenState extends State<AccountWorkspaceScreen> {
  static const _auth = AuthService();

  static const _teacher = TeacherAcademicService();

  static const _student = StudentAcademicService();

  static const _academic = AcademicService();

  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final teaching = await _teacher.loadMyCourses();

    final teachingWithCodes = <TeacherCourse>[];

    for (final course in teaching) {
      if (course.joinCode != null && course.joinCode!.isNotEmpty) {
        teachingWithCodes.add(course);
      } else {
        final code = await _teacher.getCourseJoinCode(course.id);

        teachingWithCodes.add(course.withJoinCode(code));
      }
    }

    final studies = await _academic.loadCurrentCourses();

    return _HomeData(teaching: teachingWithCodes, studies: studies);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trackademic'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              setState(_reload);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _auth.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final data = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${widget.profile.displayName}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      widget.profile.institutionId,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.extraLarge),
                    _section(
                      title: 'Teaching',
                      buttonText: 'Open teaching workspace',
                      onOpen: () => _openTeacher(),
                      child: data.teaching.isEmpty
                          ? const Text('You have not created a course yet.')
                          : Column(
                              children: [
                                for (final course in data.teaching)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.co_present_rounded,
                                    ),
                                    title: Text(
                                      '${course.code} · ${course.name}',
                                    ),
                                    subtitle: Text(
                                      'Join code: ${course.joinCode ?? '-'}',
                                    ),
                                    trailing: OutlinedButton(
                                      onPressed: () => _requests(course),
                                      child: const Text('Requests'),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    _section(
                      title: 'My studies',
                      buttonText: 'Open student workspace',
                      onOpen: () => _openStudent(),
                      extraButton: FilledButton.icon(
                        onPressed: _joinCourse,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Join course'),
                      ),
                      child: data.studies.isEmpty
                          ? const Text(
                              'You are not enrolled in any courses yet.',
                            )
                          : Column(
                              children: [
                                for (final course in data.studies)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.school_rounded),
                                    title: Text(
                                      '${course.code} · ${course.name}',
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section({
    required String title,
    required Widget child,
    required String buttonText,
    required VoidCallback onOpen,
    Widget? extraButton,
  }) {
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?extraButton,
              ],
            ),
            const SizedBox(height: AppSpacing.regular),
            child,
            const SizedBox(height: AppSpacing.regular),
            OutlinedButton(onPressed: onOpen, child: Text(buttonText)),
          ],
        ),
      ),
    );
  }

  Future<void> _joinCourse() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join course'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Join code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Request'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (code == null || code.isEmpty) {
      return;
    }

    try {
      await _student.requestJoinCourse(code);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join request sent to the course owner.')),
      );
    } on StudentAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _requests(TeacherCourse course) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _JoinRequestsDialog(
        course: course,
        onChanged: () {
          setState(_reload);
        },
      ),
    );
  }

  void _openTeacher() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RoleWorkspaceScreen(
          roleName: 'Teacher',
          destinations: WorkspaceDestinations.teacher,
          onSignOut: _auth.signOut,
        ),
      ),
    );
  }

  void _openStudent() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RoleWorkspaceScreen(
          roleName: 'Student',
          destinations: WorkspaceDestinations.student,
          onSignOut: _auth.signOut,
        ),
      ),
    );
  }
}

class _JoinRequestsDialog extends StatefulWidget {
  final TeacherCourse course;
  final VoidCallback onChanged;

  const _JoinRequestsDialog({required this.course, required this.onChanged});

  @override
  State<_JoinRequestsDialog> createState() => _JoinRequestsDialogState();
}

class _JoinRequestsDialogState extends State<_JoinRequestsDialog> {
  static const _service = TeacherAcademicService();

  late Future<List<TeacherJoinRequest>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.loadCourseJoinRequests(widget.course.id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.course.code} join requests'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: FutureBuilder<List<TeacherJoinRequest>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final requests = snapshot.data!;

            if (requests.isEmpty) {
              return const Center(child: Text('No pending join requests.'));
            }

            return ListView.separated(
              itemCount: requests.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final request = requests[index];

                return ListTile(
                  title: Text(request.studentName),
                  subtitle: Text('${request.institutionId}\n${request.email}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Reject',
                        onPressed: () => _respond(request, false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      IconButton(
                        tooltip: 'Approve',
                        onPressed: () => _respond(request, true),
                        icon: const Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                );
              },
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

  Future<void> _respond(TeacherJoinRequest request, bool approve) async {
    try {
      await _service.respondCourseJoinRequest(
        requestId: request.id,
        approve: approve,
      );

      if (!mounted) {
        return;
      }

      widget.onChanged();

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

class _HomeData {
  final List<TeacherCourse> teaching;
  final List<AcademicCourse> studies;

  const _HomeData({required this.teaching, required this.studies});
}

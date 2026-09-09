import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  static const _service = TeacherAcademicService();

  final _searchController = TextEditingController();

  late Future<List<TeacherCourse>> _coursesFuture;

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _coursesFuture = _service.loadMyCourses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeacherCourse>>(
      future: _coursesFuture,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.large),
                  _buildSearchField(),
                  const SizedBox(height: AppSpacing.large),
                  if (snapshot.connectionState != ConnectionState.done)
                    const _LoadingCard()
                  else if (snapshot.hasError)
                    _ErrorCard(
                      message: snapshot.error.toString(),
                      onRetry: _reload,
                    )
                  else
                    _buildCourseContent(snapshot.data ?? const []),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Courses',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: AppSpacing.small),
            Text(
              'Create courses and enroll registered students.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        );

        final button = FilledButton.icon(
          onPressed: _showCreateCourseDialog,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create course'),
        );

        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: AppSpacing.large),
              button,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: AppSpacing.regular),
            SizedBox(width: double.infinity, child: button),
          ],
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _searchQuery = value.trim().toLowerCase();
        });
      },
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Search by course code, name, batch, section...',
      ),
    );
  }

  Widget _buildCourseContent(List<TeacherCourse> courses) {
    final visibleCourses = courses.where((course) {
      if (_searchQuery.isEmpty) {
        return true;
      }

      final values = [
        course.code,
        course.name,
        course.department ?? '',
        course.batch ?? '',
        course.section ?? '',
        course.semester ?? '',
        course.room ?? '',
      ].join(' ').toLowerCase();

      return values.contains(_searchQuery);
    }).toList();

    if (courses.isEmpty) {
      return const _EmptyCoursesCard();
    }

    if (visibleCourses.isEmpty) {
      return const _MessageCard(
        icon: Icons.search_off_rounded,
        message: 'No courses match your search.',
      );
    }

    return Column(
      children: [
        for (final course in visibleCourses) ...[
          _CourseCard(
            course: course,
            onManageStudents: () {
              _showStudentsDialog(course);
            },
          ),
          const SizedBox(height: AppSpacing.regular),
        ],
      ],
    );
  }

  Future<void> _showCreateCourseDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return const _CreateCourseDialog();
      },
    );

    if (created == true) {
      _reload();
    }
  }

  Future<void> _showStudentsDialog(TeacherCourse course) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return _CourseStudentsDialog(course: course);
      },
    );
  }

  void _reload() {
    setState(() {
      _coursesFuture = _service.loadMyCourses();
    });
  }
}

class _CourseCard extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onManageStudents;

  const _CourseCard({required this.course, required this.onManageStudents});

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (course.department != null) course.department!,
      if (course.batch != null) course.batch!,
      if (course.section != null) course.section!,
      if (course.semester != null) course.semester!,
    ];

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.informationBackground,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.regular),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.code,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.extraSmall),
                    Text(
                      course.name,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.regular),
            Wrap(
              spacing: AppSpacing.small,
              runSpacing: AppSpacing.small,
              children: [
                for (final detail in details) _DetailChip(text: detail),
              ],
            ),
          ],
          if (course.room != null) ...[
            const SizedBox(height: AppSpacing.regular),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.small),
                Text(
                  course.room!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.large),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onManageStudents,
              icon: const Icon(Icons.group_rounded),
              label: const Text('Manage students'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateCourseDialog extends StatefulWidget {
  const _CreateCourseDialog();

  @override
  State<_CreateCourseDialog> createState() => _CreateCourseDialogState();
}

class _CreateCourseDialogState extends State<_CreateCourseDialog> {
  static const _service = TeacherAcademicService();

  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();

  final _nameController = TextEditingController();

  final _departmentController = TextEditingController();

  final _batchController = TextEditingController();

  final _sectionController = TextEditingController();

  final _semesterController = TextEditingController();

  final _roomController = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    _batchController.dispose();
    _sectionController.dispose();
    _semesterController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create course'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Course code *',
                    hintText: 'Enter course code',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Course name *'),
                  validator: _required,
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _departmentController,
                  decoration: const InputDecoration(labelText: 'Department'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _batchController,
                  decoration: const InputDecoration(labelText: 'Batch'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _sectionController,
                  decoration: const InputDecoration(labelText: 'Section'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _semesterController,
                  decoration: const InputDecoration(labelText: 'Semester'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: 'Room'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () {
                  Navigator.pop(context, false);
                },
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

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _service.createCourse(
        code: _codeController.text,
        name: _nameController.text,
        department: _optional(_departmentController.text),
        batch: _optional(_batchController.text),
        section: _optional(_sectionController.text),
        semester: _optional(_semesterController.text),
        room: _optional(_roomController.text),
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String? _optional(String value) {
    final trimmed = value.trim();

    return trimmed.isEmpty ? null : trimmed;
  }
}

class _CourseStudentsDialog extends StatefulWidget {
  final TeacherCourse course;

  const _CourseStudentsDialog({required this.course});

  @override
  State<_CourseStudentsDialog> createState() => _CourseStudentsDialogState();
}

class _CourseStudentsDialogState extends State<_CourseStudentsDialog> {
  static const _service = TeacherAcademicService();

  final _institutionIdController = TextEditingController();

  late Future<List<EnrolledStudent>> _studentsFuture;

  bool _enrolling = false;
  String? _removingStudentId;

  @override
  void initState() {
    super.initState();
    _reloadStudents();
  }

  @override
  void dispose() {
    _institutionIdController.dispose();
    super.dispose();
  }

  void _reloadStudents() {
    _studentsFuture = _service.loadCourseStudents(widget.course.id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.course.code} students'),
      content: SizedBox(
        width: 650,
        height: 460,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _institutionIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Student institution ID',
                      hintText: 'Enter a registered user ID',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.medium),
                FilledButton.icon(
                  onPressed: _enrolling ? null : _enroll,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Enroll'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            Expanded(
              child: FutureBuilder<List<EnrolledStudent>>(
                future: _studentsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    );
                  }

                  final students = snapshot.data ?? const [];

                  if (students.isEmpty) {
                    return const Center(
                      child: Text(
                        'No students are enrolled in this course yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final student = students[index];

                      final removing = _removingStudentId == student.uid;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_rounded),
                        ),
                        title: Text(student.displayName),
                        subtitle: Text(
                          '${student.institutionId} · ${student.email}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove student',
                          onPressed: removing
                              ? null
                              : () {
                                  _confirmRemove(student);
                                },
                          icon: removing
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_remove_outlined,
                                  color: AppColors.danger,
                                ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _enroll() async {
    final institutionId = _institutionIdController.text.trim();

    if (institutionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a student institution ID.')),
      );

      return;
    }

    setState(() {
      _enrolling = true;
    });

    try {
      await _service.enrollStudent(
        courseId: widget.course.id,
        institutionId: institutionId,
      );

      if (!mounted) {
        return;
      }

      _institutionIdController.clear();

      setState(_reloadStudents);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student enrolled successfully.')),
      );
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _enrolling = false;
        });
      }
    }
  }

  Future<void> _confirmRemove(EnrolledStudent student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove student?'),
          content: Text(
            'Remove ${student.displayName} '
            '(${student.institutionId}) from '
            '${widget.course.code}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _remove(student);
  }

  Future<void> _remove(EnrolledStudent student) async {
    setState(() {
      _removingStudentId = student.uid;
    });

    try {
      await _service.unenrollStudent(
        courseId: widget.course.id,
        studentId: student.uid,
      );

      if (!mounted) {
        return;
      }

      setState(_reloadStudents);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${student.displayName} removed from the course.'),
        ),
      );
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _removingStudentId = null;
        });
      }
    }
  }
}

class _DetailChip extends StatelessWidget {
  final String text;

  const _DetailChip({required this.text});

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
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyCoursesCard extends StatelessWidget {
  const _EmptyCoursesCard();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.menu_book_outlined,
      message:
          'You have not created any courses yet. Create your first course to begin.',
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _MessageCard({required this.icon, required this.message});

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
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.medium),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.hourglass_top_rounded,
      message: 'Loading your courses...',
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
            color: AppColors.danger,
            size: 44,
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

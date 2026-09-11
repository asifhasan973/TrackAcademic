import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/teacher/students/presentation/teacher_student_record_screen.dart';

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  static const _service = TeacherAcademicService();

  final _searchController = TextEditingController();

  late Future<List<TeacherCourse>> _coursesFuture;

  bool _showArchived = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _coursesFuture = _service.loadMyCourses(includeArchived: true);
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
    final activeCount = courses.where((c) => c.isActive).length;
    final archivedCount = courses.where((c) => !c.isActive).length;

    final tabCourses = courses.where((course) {
      return _showArchived ? !course.isActive : course.isActive;
    }).toList();

    final visibleCourses = tabCourses.where((course) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment<bool>(
              value: false,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text('Active ($activeCount)'),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: Text('Archived ($archivedCount)'),
            ),
          ],
          selected: {_showArchived},
          onSelectionChanged: (selection) {
            setState(() {
              _showArchived = selection.first;
            });
          },
        ),
        const SizedBox(height: AppSpacing.large),
        if (courses.isEmpty)
          const _EmptyCoursesCard()
        else if (tabCourses.isEmpty)
          _MessageCard(
            icon: _showArchived
                ? Icons.archive_outlined
                : Icons.menu_book_outlined,
            message: _showArchived
                ? 'No archived courses found.'
                : 'No active courses. Create your first course to begin.',
          )
        else if (visibleCourses.isEmpty)
          const _MessageCard(
            icon: Icons.search_off_rounded,
            message: 'No courses match your search.',
          )
        else
          Column(
            children: [
              for (final course in visibleCourses) ...[
                _CourseCard(
                  course: course,
                  onManageStudents: () => _showStudentsDialog(course),
                  onEdit: () => _showEditCourseDialog(course),
                  onArchive: () => _confirmArchiveCourse(course),
                  onReactivate: () => _confirmReactivateCourse(course),
                ),
                const SizedBox(height: AppSpacing.regular),
              ],
            ],
          ),
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

  Future<void> _showEditCourseDialog(TeacherCourse course) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _EditCourseDialog(course: course),
    );

    if (updated == true) {
      _reload();
    }
  }

  Future<void> _confirmArchiveCourse(TeacherCourse course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Archive ${course.code}?'),
          content: const Text(
            'Archiving this course will make its schedules, assessments, '
            'and student enrollment read-only.\n\n'
            'Please ensure any active attendance session is closed before archiving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive course'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _service.archiveCourse(course.id);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${course.code} has been archived.')),
        );
      }
    } on TeacherAcademicServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _confirmReactivateCourse(TeacherCourse course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Reactivate ${course.code}?'),
          content: const Text(
            'Reactivating this course will restore full editing permissions '
            'for attendance sessions, schedules, assessments, and marks.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reactivate course'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _service.reactivateCourse(course.id);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${course.code} has been reactivated.')),
        );
      }
    } on TeacherAcademicServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
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
      _coursesFuture = _service.loadMyCourses(includeArchived: true);
    });
  }
}

class _CourseCard extends StatelessWidget {
  final TeacherCourse course;
  final VoidCallback onManageStudents;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onReactivate;

  const _CourseCard({
    required this.course,
    required this.onManageStudents,
    required this.onEdit,
    required this.onArchive,
    required this.onReactivate,
  });

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
                    Row(
                      children: [
                        Text(
                          course.code,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (!course.isActive) ...[
                          const SizedBox(width: AppSpacing.small),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warningBackground,
                              borderRadius: BorderRadius.circular(
                                AppRadius.small,
                              ),
                              border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.archive_outlined,
                                  size: 13,
                                  color: AppColors.warning,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Archived',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.small,
              runSpacing: AppSpacing.small,
              children: [
                if (course.isActive) ...[
                  OutlinedButton.icon(
                    onPressed: onManageStudents,
                    icon: const Icon(Icons.group_rounded, size: 18),
                    label: const Text('Manage students'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit course'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onArchive,
                    icon: const Icon(
                      Icons.archive_outlined,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    label: const Text(
                      'Archive',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: onManageStudents,
                    icon: const Icon(Icons.group_rounded, size: 18),
                    label: const Text('View students'),
                  ),
                  FilledButton.icon(
                    onPressed: onReactivate,
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Reactivate course'),
                  ),
                ],
              ],
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

class _EditCourseDialog extends StatefulWidget {
  final TeacherCourse course;

  const _EditCourseDialog({required this.course});

  @override
  State<_EditCourseDialog> createState() => _EditCourseDialogState();
}

class _EditCourseDialogState extends State<_EditCourseDialog> {
  static const _service = TeacherAcademicService();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _departmentController;
  late final TextEditingController _batchController;
  late final TextEditingController _sectionController;
  late final TextEditingController _semesterController;
  late final TextEditingController _roomController;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course.name);
    _departmentController = TextEditingController(
      text: widget.course.department ?? '',
    );
    _batchController = TextEditingController(text: widget.course.batch ?? '');
    _sectionController = TextEditingController(
      text: widget.course.section ?? '',
    );
    _semesterController = TextEditingController(
      text: widget.course.semester ?? '',
    );
    _roomController = TextEditingController(text: widget.course.room ?? '');
  }

  @override
  void dispose() {
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
      title: Text('Edit ${widget.course.code}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.medium),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.small),
                      Text(
                        'Course code: ${widget.course.code}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Course name *'),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Course name is required';
                    }
                    return null;
                  },
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
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await _service.updateCourse(
        courseId: widget.course.id,
        name: _nameController.text.trim(),
        department: _optional(_departmentController.text),
        batch: _optional(_batchController.text),
        section: _optional(_sectionController.text),
        semester: _optional(_semesterController.text),
        room: _optional(_roomController.text),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on TeacherAcademicServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
  bool _showInactive = false;
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
    _studentsFuture = _service.loadCourseStudents(
      widget.course.id,
      includeInactive: _showInactive,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.course.code} students'),
      content: SizedBox(
        width: 650,
        height: 500,
        child: Column(
          children: [
            if (!widget.course.isActive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.medium),
                margin: const EdgeInsets.only(bottom: AppSpacing.small),
                decoration: BoxDecoration(
                  color: AppColors.warningBackground,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: AppSpacing.small),
                    Expanded(
                      child: Text(
                        'This course is archived. Enrolling and removing students is disabled.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
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
            const SizedBox(height: AppSpacing.small),
            Row(
              children: [
                Checkbox(
                  value: _showInactive,
                  onChanged: (val) {
                    setState(() {
                      _showInactive = val ?? false;
                      _reloadStudents();
                    });
                  },
                ),
                const Text(
                  'Show past / inactive enrollments',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.small),
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
                      final isEnrolled = student.isActive;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isEnrolled
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.person_rounded,
                            color: isEnrolled
                                ? AppColors.primary
                                : Colors.amber[800],
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(student.displayName),
                            if (!isEnrolled) ...[
                              const SizedBox(width: AppSpacing.small),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.small,
                                  ),
                                ),
                                child: Text(
                                  'Inactive',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber[900],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${student.institutionId} · ${student.email}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View academic record',
                              icon: const Icon(
                                Icons.analytics_outlined,
                                color: AppColors.primary,
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => TeacherStudentRecordScreen(
                                      course: widget.course,
                                      student: student,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (isEnrolled && widget.course.isActive)
                              IconButton(
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
                          ],
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

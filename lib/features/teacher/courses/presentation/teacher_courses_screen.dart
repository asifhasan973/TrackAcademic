import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/core/widgets/inline_error_banner.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';
import 'package:trackademic/features/teacher/students/presentation/teacher_student_record_screen.dart';

class TeacherCoursesScreen extends StatefulWidget {
  final String? initialManageCourseId;
  final String? initialRequestId;
  final int? initialTabIndex;

  const TeacherCoursesScreen({
    this.initialManageCourseId,
    this.initialRequestId,
    this.initialTabIndex,
    super.key,
  });

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  static const _service = TeacherAcademicService();

  final _searchController = TextEditingController();

  late Future<List<TeacherCourse>> _coursesFuture;

  bool _showArchived = false;
  String _searchQuery = '';
  String? _handledInitialCourseId;

  @override
  void initState() {
    super.initState();
    _coursesFuture = _service.loadMyCourses(includeArchived: true);
    if (widget.initialManageCourseId != null) {
      _checkAndOpenInitialDialog();
    }
  }

  @override
  void didUpdateWidget(covariant TeacherCoursesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialManageCourseId != null &&
        widget.initialManageCourseId != oldWidget.initialManageCourseId) {
      _checkAndOpenInitialDialog();
    }
  }

  Future<void> _checkAndOpenInitialDialog() async {
    final courseId = widget.initialManageCourseId;
    if (courseId == null || _handledInitialCourseId == courseId) return;
    _handledInitialCourseId = courseId;

    final courses = await _coursesFuture;
    if (!mounted) return;
    final course = courses.where((c) => c.id == courseId).firstOrNull;
    if (course != null) {
      _showStudentsDialog(
        course,
        initialTabIndex: widget.initialTabIndex ?? 0,
        initialRequestId: widget.initialRequestId,
      );
    }
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
                  onTiming: () => _openCourseTiming(course),
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

  void _openCourseTiming(TeacherCourse course) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('${course.code} Timing')),
          body: TeacherScheduleScreen(initialCourseId: course.id),
        ),
      ),
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

  Future<void> _showStudentsDialog(
    TeacherCourse course, {
    int initialTabIndex = 0,
    String? initialRequestId,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return CourseStudentsDialog(
          course: course,
          initialTabIndex: initialTabIndex,
          initialRequestId: initialRequestId,
          onChanged: _reload,
        );
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
  final VoidCallback onTiming;
  final VoidCallback onManageStudents;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onReactivate;

  const _CourseCard({
    required this.course,
    required this.onTiming,
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
          const SizedBox(height: AppSpacing.regular),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.medium,
              vertical: AppSpacing.small,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: AppColors.border),
            ),
            child: Wrap(
              spacing: AppSpacing.large,
              runSpacing: AppSpacing.small,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Course ID: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: SelectableText(
                        course.id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy Course ID',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: AppColors.primary,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: course.id));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied Course ID: ${course.id}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Join code: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SelectableText(
                      course.joinCode ?? '-',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy Join Code',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: AppColors.primary,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: course.joinCode ?? ''),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied Join code: ${course.joinCode ?? '-'}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              const buttonHeight = 42.0;
              final buttonShape = RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.small),
              );

              final timingBtn = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, buttonHeight),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onTiming,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(course.isActive ? 'Timing' : 'View timing'),
              );

              final manageBtn = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, buttonHeight),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onManageStudents,
                icon: const Icon(Icons.group_rounded, size: 18),
                label: Text(
                  course.isActive ? 'Manage students' : 'View students',
                ),
              );

              final editBtn = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, buttonHeight),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit course'),
              );

              final archiveBtn = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  backgroundColor: AppColors.error.withValues(alpha: 0.04),
                  minimumSize: const Size(0, buttonHeight),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onArchive,
                icon: const Icon(
                  Icons.archive_outlined,
                  size: 18,
                  color: AppColors.error,
                ),
                label: const Text(
                  'Archive',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );

              final reactivateBtn = FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, buttonHeight),
                  shape: buttonShape,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onReactivate,
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Reactivate course'),
              );

              if (course.isActive) {
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      timingBtn,
                      const SizedBox(height: 8),
                      manageBtn,
                      const SizedBox(height: 8),
                      editBtn,
                      const SizedBox(height: 8),
                      archiveBtn,
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: timingBtn),
                        const SizedBox(width: 8),
                        Expanded(child: manageBtn),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: editBtn),
                        const SizedBox(width: 8),
                        Expanded(child: archiveBtn),
                      ],
                    ),
                  ],
                );
              } else {
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      timingBtn,
                      const SizedBox(height: 8),
                      manageBtn,
                      const SizedBox(height: 8),
                      reactivateBtn,
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: timingBtn),
                        const SizedBox(width: 8),
                        Expanded(child: manageBtn),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: reactivateBtn,
                    ),
                  ],
                );
              }
            },
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

class CourseStudentsDialog extends StatefulWidget {
  final TeacherCourse course;
  final int initialTabIndex;
  final String? initialRequestId;
  final VoidCallback? onChanged;

  const CourseStudentsDialog({
    required this.course,
    this.initialTabIndex = 0,
    this.initialRequestId,
    this.onChanged,
    super.key,
  });

  @override
  State<CourseStudentsDialog> createState() => _CourseStudentsDialogState();
}

class _CourseStudentsDialogState extends State<CourseStudentsDialog> {
  static const _service = TeacherAcademicService();

  final _institutionIdController = TextEditingController();

  late Future<List<TeacherJoinRequest>> _requestsFuture;
  late Future<List<EnrolledStudent>> _studentsFuture;

  bool _enrolling = false;
  bool _showInactive = false;
  String? _removingStudentId;
  String? _processingRequestId;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _reloadRequests();
    _reloadStudents();
  }

  @override
  void dispose() {
    _institutionIdController.dispose();
    super.dispose();
  }

  void _reloadRequests() {
    _requestsFuture = _service.loadCourseJoinRequests(widget.course.id);
  }

  void _reloadStudents() {
    _studentsFuture = _service.loadCourseStudents(
      widget.course.id,
      includeInactive: _showInactive,
    );
  }

  Future<void> _respond(TeacherJoinRequest request, bool approve) async {
    if (!widget.course.isActive && approve) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot approve requests for an archived course.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_processingRequestId != null) {
      return;
    }

    setState(() {
      _processingRequestId = request.id;
    });

    try {
      await _service.respondCourseJoinRequest(
        requestId: request.id,
        approve: approve,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '${request.studentName} has been approved.'
                : '${request.studentName} has been rejected.',
          ),
          backgroundColor: approve ? AppColors.success : null,
        ),
      );

      widget.onChanged?.call();

      setState(() {
        _reloadRequests();
        _reloadStudents();
      });
    } on TeacherAcademicServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _dialogError = error.message;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingRequestId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogWidth = math.min(650.0, mediaQuery.size.width - 24);
    final dialogHeight = math.min(540.0, mediaQuery.size.height - 80);
    final isNarrow = mediaQuery.size.width < 420;

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.small),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                Expanded(
                  child: Text(
                    '${widget.course.code} Students',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_dialogError != null) ...[
              const SizedBox(height: AppSpacing.small),
              InlineErrorBanner(
                message: _dialogError!,
                onDismiss: () => setState(() => _dialogError = null),
              ),
            ],
            const SizedBox(height: AppSpacing.medium),
            FutureBuilder<List<TeacherJoinRequest>>(
              future: _requestsFuture,
              builder: (context, reqSnap) {
                final pendingCount = reqSnap.hasData ? reqSnap.data!.length : 0;
                return TabBar(
                  isScrollable: isNarrow,
                  tabAlignment: isNarrow ? TabAlignment.start : TabAlignment.fill,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Pending requests'),
                          if (pendingCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(text: 'Enrolled students'),
                  ],
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: TabBarView(
            children: [_buildPendingRequestsTab(), _buildEnrolledStudentsTab()],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsTab() {
    return Column(
      children: [
        if (!widget.course.isActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.medium),
            margin: const EdgeInsets.only(top: 8, bottom: 8),
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
                    'This course is archived. Approving join requests is disabled.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<TeacherJoinRequest>>(
            future: _requestsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      OutlinedButton.icon(
                        onPressed: () => setState(_reloadRequests),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final requests = snapshot.data ?? const [];

              if (requests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group_add_outlined,
                        size: 48,
                        color: AppColors.textTertiary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      const Text(
                        'No pending join requests.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: requests.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  final isProcessing = _processingRequestId == request.id;
                  final isTarget = widget.initialRequestId == request.id;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isTarget
                          ? AppColors.primary.withValues(alpha: 0.05)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(
                        color: isTarget
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.border,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 440;
                        final actionButtons = isProcessing
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.danger,
                                      side: const BorderSide(
                                        color: AppColors.danger,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: _processingRequestId != null
                                        ? null
                                        : () => _respond(request, false),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Reject'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: (_processingRequestId != null ||
                                            !widget.course.isActive)
                                        ? null
                                        : () => _respond(request, true),
                                    icon: const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Approve'),
                                  ),
                                ],
                              );

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    child: const Icon(
                                      Icons.person_outline_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request.studentName.isNotEmpty
                                              ? request.studentName
                                              : 'Student',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${request.institutionId} · ${request.email}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actionButtons,
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              child: const Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.studentName.isNotEmpty
                                        ? request.studentName
                                        : 'Student',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${request.institutionId} · ${request.email}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            actionButtons,
                          ],
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEnrolledStudentsTab() {
    return Column(
      children: [
        if (!widget.course.isActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.medium),
            margin: const EdgeInsets.only(top: 8, bottom: AppSpacing.small),
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
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
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
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                      const SizedBox(height: AppSpacing.medium),
                      OutlinedButton.icon(
                        onPressed: () => setState(_reloadStudents),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
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
                        Flexible(
                          child: Text(
                            student.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
      widget.onChanged?.call();

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
      widget.onChanged?.call();

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

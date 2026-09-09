import 'package:flutter/material.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TeacherMarksScreen extends StatefulWidget {
  const TeacherMarksScreen({super.key});

  @override
  State<TeacherMarksScreen> createState() => _TeacherMarksScreenState();
}

class _TeacherMarksScreenState extends State<TeacherMarksScreen> {
  static const _service = TeacherAcademicService();

  late Future<_MarksPageData> _future;

  String? _courseId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MarksPageData> _load() async {
    final courses = await _service.loadMyCourses();

    if (courses.isEmpty) {
      return _MarksPageData(
        courses: courses,
        selectedCourseId: null,
        assessments: const [],
      );
    }

    final selected = _courseId ?? courses.first.id;

    _courseId = selected;

    return _MarksPageData(
      courses: courses,
      selectedCourseId: selected,
      assessments: await _service.loadAssessmentsForCourse(selected),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MarksPageData>(
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
                  const Text(
                    'Marks',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const Text(
                    'Create assessments, enter student marks, and publish results.',
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

  Widget _content(_MarksPageData data) {
    if (data.courses.isEmpty) {
      return const Text('Create a course before managing marks.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: data.selectedCourseId,
                decoration: const InputDecoration(labelText: 'Course'),
                items: data.courses
                    .map(
                      (course) => DropdownMenuItem(
                        value: course.id,
                        child: Text('${course.code} · ${course.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  _courseId = value;
                  _reload();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.medium),
            FilledButton.icon(
              onPressed: () => _createAssessment(data.selectedCourseId!),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New assessment'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.large),
        if (data.assessments.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.extraLarge),
              child: Text('No assessments created for this course.'),
            ),
          )
        else
          for (final assessment in data.assessments) ...[
            _AssessmentCard(
              assessment: assessment,
              onEnterMarks: () => _enterMarks(assessment),
              onEdit: assessment.status == 'draft'
                  ? () => _editAssessment(assessment)
                  : null,
              onDelete: assessment.status == 'draft'
                  ? () => _deleteAssessment(assessment)
                  : null,
              onPublish: assessment.status == 'published'
                  ? null
                  : () => _publish(assessment),
            ),
            const SizedBox(height: AppSpacing.regular),
          ],
      ],
    );
  }

  Future<void> _createAssessment(String courseId) async {
    final nameController = TextEditingController();
    final maxController = TextEditingController(text: '20');
    final dateController = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    String type = 'Quiz';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create assessment'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Assessment name',
                    hintText: 'e.g. Class Test 1',
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Assessment type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Quiz', child: Text('Quiz')),
                    DropdownMenuItem(value: 'Midterm', child: Text('Midterm')),
                    DropdownMenuItem(
                      value: 'Final Exam',
                      child: Text('Final Exam'),
                    ),
                    DropdownMenuItem(
                      value: 'Assignment',
                      child: Text('Assignment'),
                    ),
                    DropdownMenuItem(
                      value: 'Presentation',
                      child: Text('Presentation'),
                    ),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => type = val);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextField(
                  controller: maxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Maximum marks'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date (YYYY-MM-DD)',
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      final y = picked.year.toString();
                      final m = picked.month.toString().padLeft(2, '0');
                      final d = picked.day.toString().padLeft(2, '0');
                      setDialogState(() {
                        dateController.text = '$y-$m-$d';
                      });
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
              onPressed: () async {
                final max = double.tryParse(maxController.text);
                final name = nameController.text.trim();
                final date = dateController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an assessment name.'),
                    ),
                  );
                  return;
                }
                if (max == null || max <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid maximum mark.'),
                    ),
                  );
                  return;
                }

                try {
                  await _service.createAssessment(
                    courseId: courseId,
                    name: name,
                    type: type,
                    maxScore: max,
                    date: date,
                  );

                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } on TeacherAcademicServiceException catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    maxController.dispose();
    dateController.dispose();

    if (result == true) {
      _reload();
    }
  }

  Future<void> _editAssessment(TeacherAssessment assessment) async {
    final nameController = TextEditingController(text: assessment.name);
    final maxController = TextEditingController(
      text: assessment.maxScore.toStringAsFixed(0),
    );
    final dateController = TextEditingController(
      text: assessment.date.isNotEmpty
          ? assessment.date
          : DateTime.now().toIso8601String().substring(0, 10),
    );
    String type = assessment.type.isNotEmpty ? assessment.type : 'Quiz';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit draft assessment'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Assessment name',
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Assessment type',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Quiz', child: Text('Quiz')),
                    DropdownMenuItem(value: 'Midterm', child: Text('Midterm')),
                    DropdownMenuItem(
                      value: 'Final Exam',
                      child: Text('Final Exam'),
                    ),
                    DropdownMenuItem(
                      value: 'Assignment',
                      child: Text('Assignment'),
                    ),
                    DropdownMenuItem(
                      value: 'Presentation',
                      child: Text('Presentation'),
                    ),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => type = val);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextField(
                  controller: maxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Maximum marks'),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date (YYYY-MM-DD)',
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(dateController.text) ??
                          DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      final y = picked.year.toString();
                      final m = picked.month.toString().padLeft(2, '0');
                      final d = picked.day.toString().padLeft(2, '0');
                      setDialogState(() {
                        dateController.text = '$y-$m-$d';
                      });
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
              onPressed: () async {
                final max = double.tryParse(maxController.text);
                final name = nameController.text.trim();
                final date = dateController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter an assessment name.'),
                    ),
                  );
                  return;
                }
                if (max == null || max <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid maximum mark.'),
                    ),
                  );
                  return;
                }

                try {
                  await _service.updateAssessment(
                    assessmentId: assessment.id,
                    name: name,
                    type: type,
                    maxScore: max,
                    date: date,
                  );

                  if (context.mounted) {
                    Navigator.pop(context, true);
                  }
                } on TeacherAcademicServiceException catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    maxController.dispose();
    dateController.dispose();

    if (result == true) {
      _reload();
    }
  }

  Future<void> _deleteAssessment(TeacherAssessment assessment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft assessment?'),
        content: Text(
          'Are you sure you want to delete "${assessment.name}"? '
          'This will permanently delete this draft assessment and all its entered marks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteAssessment(assessment.id);
        _reload();
      } on TeacherAcademicServiceException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    }
  }

  Future<void> _enterMarks(TeacherAssessment assessment) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _MarksEditorDialog(assessment: assessment),
    );

    if (changed == true) {
      _reload();
    }
  }

  Future<void> _publish(TeacherAssessment assessment) async {
    try {
      await _service.publishAssessment(assessment.id);

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

class _MarksEditorDialog extends StatefulWidget {
  final TeacherAssessment assessment;

  const _MarksEditorDialog({required this.assessment});

  @override
  State<_MarksEditorDialog> createState() => _MarksEditorDialogState();
}

class _MarksEditorDialogState extends State<_MarksEditorDialog> {
  static const _service = TeacherAcademicService();

  late Future<_EditorData> _future;

  final Map<String, double> _scores = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _future = _load();
  }

  Future<_EditorData> _load() async {
    final students = await _service.loadCourseStudents(
      widget.assessment.courseId,
    );

    final marks = await _service.loadAssessmentMarks(widget.assessment);

    for (final mark in marks) {
      _scores[mark.studentId] = mark.score;
    }

    return _EditorData(students: students);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.assessment.name} · ${widget.assessment.courseCode}',
      ),
      content: SizedBox(
        width: 650,
        height: 450,
        child: FutureBuilder<_EditorData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final students = snapshot.data!.students;

            if (students.isEmpty) {
              return const Center(
                child: Text('No students enrolled in this course.'),
              );
            }

            return ListView.separated(
              itemCount: students.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final student = students[index];

                return Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(student.displayName),
                        subtitle: Text(student.institutionId),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        initialValue: _scores[student.uid]?.toString() ?? '',
                        enabled: widget.assessment.status != 'published',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          suffixText:
                              '/${widget.assessment.maxScore.toStringAsFixed(0)}',
                        ),
                        onChanged: (value) {
                          final score = double.tryParse(value);

                          if (score == null) {
                            _scores.remove(student.uid);
                          } else {
                            _scores[student.uid] = score;
                          }
                        },
                      ),
                    ),
                    if (widget.assessment.status == 'published') ...[
                      const SizedBox(width: AppSpacing.small),
                      IconButton(
                        tooltip: 'Correct published mark',
                        icon: const Icon(
                          Icons.edit_note,
                          color: AppColors.primary,
                        ),
                        onPressed: () => _correctMark(student),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (widget.assessment.status != 'published')
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save marks'),
          ),
      ],
    );
  }

  Future<void> _correctMark(EnrolledStudent student) async {
    final currentScore = _scores[student.uid] ?? 0.0;
    final scoreController = TextEditingController(
      text: currentScore.toStringAsFixed(1),
    );
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Correct Mark · ${widget.assessment.name}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Student: ${student.displayName} (${student.institutionId})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: scoreController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'New score',
                  suffixText:
                      '/${widget.assessment.maxScore.toStringAsFixed(1)}',
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Correction reason',
                  hintText: 'e.g., Regraded problem 2; adjusted mark',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newScore = double.tryParse(scoreController.text.trim());
              final reason = reasonController.text.trim();

              if (newScore == null ||
                  newScore < 0 ||
                  newScore > widget.assessment.maxScore) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Score must be between 0 and ${widget.assessment.maxScore.toStringAsFixed(1)}.',
                    ),
                  ),
                );
                return;
              }

              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('A non-empty correction reason is required.'),
                  ),
                );
                return;
              }

              try {
                await _service.correctPublishedMark(
                  assessmentId: widget.assessment.id,
                  studentId: student.uid,
                  newScore: newScore,
                  reason: reason,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx, true);
                }
              } on TeacherAcademicServiceException catch (error) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                }
              }
            },
            child: const Text('Submit correction'),
          ),
        ],
      ),
    );

    scoreController.dispose();
    reasonController.dispose();

    if (result == true) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<void> _save() async {
    for (final score in _scores.values) {
      if (score < 0 || score > widget.assessment.maxScore) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A score is outside the allowed range.'),
          ),
        );

        return;
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      await _service.saveAssessmentMarks(
        assessmentId: widget.assessment.id,
        marks: _scores,
      );

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
          _saving = false;
        });
      }
    }
  }
}

class _AssessmentCard extends StatelessWidget {
  final TeacherAssessment assessment;
  final VoidCallback onEnterMarks;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;

  const _AssessmentCard({
    required this.assessment,
    required this.onEnterMarks,
    this.onEdit,
    this.onDelete,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final dateDisplay = assessment.date.isNotEmpty
        ? ' · Date: ${assessment.date}'
        : '';

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        title: Row(
          children: [
            Text('${assessment.name} · ${assessment.courseCode}'),
            const SizedBox(width: AppSpacing.small),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(
                assessment.type,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Maximum: ${assessment.maxScore.toStringAsFixed(0)}$dateDisplay · ${assessment.status}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: onEnterMarks,
              child: Text(
                assessment.status == 'published' ? 'View marks' : 'Enter marks',
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: AppSpacing.small),
              IconButton(
                tooltip: 'Edit assessment',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
            if (onDelete != null) ...[
              IconButton(
                tooltip: 'Delete draft assessment',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: onDelete,
              ),
            ],
            if (onPublish != null) ...[
              const SizedBox(width: AppSpacing.small),
              FilledButton(onPressed: onPublish, child: const Text('Publish')),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarksPageData {
  final List<TeacherCourse> courses;
  final String? selectedCourseId;
  final List<TeacherAssessment> assessments;

  const _MarksPageData({
    required this.courses,
    required this.selectedCourseId,
    required this.assessments,
  });
}

class _EditorData {
  final List<EnrolledStudent> students;

  const _EditorData({required this.students});
}

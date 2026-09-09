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

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                  hintText: 'CT 1',
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Maximum marks'),
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

              if (max == null) {
                return;
              }

              try {
                await _service.createAssessment(
                  courseId: courseId,
                  name: nameController.text.trim(),
                  maxScore: max,
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
    );

    nameController.dispose();
    maxController.dispose();

    if (result == true) {
      _reload();
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
  final VoidCallback? onPublish;

  const _AssessmentCard({
    required this.assessment,
    required this.onEnterMarks,
    required this.onPublish,
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
        title: Text('${assessment.name} · ${assessment.courseCode}'),
        subtitle: Text(
          'Maximum: ${assessment.maxScore.toStringAsFixed(0)} · ${assessment.status}',
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

import 'package:flutter/material.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/ui_preview/presentation/role_workspace_screen.dart';

class RolePreviewScreen extends StatelessWidget {
  const RolePreviewScreen({super.key});

  static const teacherDestinations = [
    WorkspaceDestination(
      label: 'Dashboard',
      description:
          'Overview of courses, attendance sessions, student activity, and upcoming classes.',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    WorkspaceDestination(
      label: 'Attendance',
      description:
          'Create secured attendance sessions and monitor student participation.',
      icon: Icons.how_to_reg_outlined,
      selectedIcon: Icons.how_to_reg_rounded,
    ),
    WorkspaceDestination(
      label: 'Courses',
      description:
          'Manage assigned courses, enrolled students, and course information.',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
    ),
    WorkspaceDestination(
      label: 'Marks',
      description:
          'Enter and manage CT marks, attendance marks, and academic results.',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics_rounded,
    ),
    WorkspaceDestination(
      label: 'Schedule',
      description: 'Create, view, and update regular class schedules.',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
  ];

  static const studentDestinations = [
    WorkspaceDestination(
      label: 'Dashboard',
      description:
          'Overview of attendance percentage, marks, courses, and upcoming classes.',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    WorkspaceDestination(
      label: 'Attendance',
      description:
          'Mark attendance securely and review previous attendance records.',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check_rounded,
    ),
    WorkspaceDestination(
      label: 'Marks',
      description: 'Review CT marks, attendance marks, and academic progress.',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
    ),
    WorkspaceDestination(
      label: 'Schedule',
      description: 'View regular classes and recently updated schedules.',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
    WorkspaceDestination(
      label: 'Profile',
      description: 'Review personal information and academic privacy settings.',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trackademic UI Preview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.regular),
                  decoration: BoxDecoration(
                    color: AppColors.warningBackground,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.science_outlined, color: AppColors.warning),
                      SizedBox(width: AppSpacing.medium),
                      Expanded(
                        child: Text(
                          'Development preview: role selection will not '
                          'appear in the final application. Firebase will '
                          'determine the authenticated user’s role.',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.extraLarge),
                const Text(
                  'Choose an interface to preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.small),
                const Text(
                  'Your access depends on the courses you create and the courses you join.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.extraLarge),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 760;
                    final width = isWide
                        ? (constraints.maxWidth - AppSpacing.regular) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: AppSpacing.regular,
                      runSpacing: AppSpacing.regular,
                      children: [
                        SizedBox(
                          width: width,
                          child: _RoleCard(
                            icon: Icons.co_present_rounded,
                            title: 'Teacher Preview',
                            description:
                                'Manage courses, attendance sessions, '
                                'marks, schedules, and student records.',
                            features: const [
                              'Create attendance sessions',
                              'Manage CT and attendance marks',
                              'Update class schedules',
                            ],
                            buttonText: 'Open teacher workspace',
                            onPressed: () {
                              _openWorkspace(
                                context,
                                roleName: 'Teacher',
                                destinations: teacherDestinations,
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _RoleCard(
                            icon: Icons.school_rounded,
                            title: 'Student Preview',
                            description:
                                'View attendance, marks, schedules, '
                                'courses, and private academic records.',
                            features: const [
                              'Mark secured attendance',
                              'Review academic progress',
                              'View updated schedules',
                            ],
                            buttonText: 'Open student workspace',
                            onPressed: () {
                              _openWorkspace(
                                context,
                                roleName: 'Student',
                                destinations: studentDestinations,
                              );
                            },
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
      ),
    );
  }

  void _openWorkspace(
    BuildContext context, {
    required String roleName,
    required List<WorkspaceDestination> destinations,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            RoleWorkspaceScreen(roleName: roleName, destinations: destinations),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> features;
  final String buttonText;
  final VoidCallback onPressed;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.informationBackground,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: AppSpacing.large),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          Text(
            description,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.large),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.medium),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.medium),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: Text(buttonText)),
          ),
        ],
      ),
    );
  }
}

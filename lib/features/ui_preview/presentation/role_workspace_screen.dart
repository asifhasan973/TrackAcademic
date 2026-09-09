import 'package:flutter/material.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';
import 'package:trackademic/features/student/attendance/presentation/student_attendance_screen.dart';
import 'package:trackademic/features/student/dashboard/presentation/student_dashboard_screen.dart';
import 'package:trackademic/features/student/marks/presentation/student_marks_screen.dart';
import 'package:trackademic/features/student/profile/presentation/student_profile_screen.dart';
import 'package:trackademic/features/student/schedule/presentation/student_schedule_screen.dart';
import 'package:trackademic/features/teacher/attendance/presentation/teacher_create_attendance_screen.dart';
import 'package:trackademic/features/teacher/courses/presentation/teacher_courses_screen.dart';
import 'package:trackademic/features/teacher/dashboard/presentation/teacher_dashboard_screen.dart';
import 'package:trackademic/features/teacher/marks/presentation/teacher_marks_screen.dart';
import 'package:trackademic/features/teacher/schedule/presentation/teacher_schedule_screen.dart';

class WorkspaceDestination {
  final String label;
  final String description;
  final IconData icon;
  final IconData selectedIcon;

  const WorkspaceDestination({
    required this.label,
    required this.description,
    required this.icon,
    required this.selectedIcon,
  });
}

abstract final class WorkspaceDestinations {
  static const teacher = <WorkspaceDestination>[
    WorkspaceDestination(
      label: 'Dashboard',
      description:
          'Overview of courses, attendance sessions, student activity, '
          'and upcoming classes.',
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
    WorkspaceDestination(
      label: 'Profile',
      description: 'Manage your Trackademic account and academic information.',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  static const student = <WorkspaceDestination>[
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
}

class RoleWorkspaceScreen extends StatefulWidget {
  final String roleName;
  final List<WorkspaceDestination> destinations;
  final Future<void> Function()? onSignOut;

  const RoleWorkspaceScreen({
    required this.roleName,
    required this.destinations,
    this.onSignOut,
    super.key,
  });

  @override
  State<RoleWorkspaceScreen> createState() => _RoleWorkspaceScreenState();
}

class _RoleWorkspaceScreenState extends State<RoleWorkspaceScreen> {
  int _selectedIndex = 0;
  bool _isSigningOut = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final destination = widget.destinations[_selectedIndex];

    final Widget content;

    if (widget.roleName == 'Teacher' && _selectedIndex == 0) {
      content = const TeacherDashboardScreen();
    } else if (widget.roleName == 'Teacher' && _selectedIndex == 1) {
      content = const TeacherCreateAttendanceScreen();
    } else if (widget.roleName == 'Teacher' && _selectedIndex == 2) {
      content = const TeacherCoursesScreen();
    } else if (widget.roleName == 'Teacher' && _selectedIndex == 3) {
      content = const TeacherMarksScreen();
    } else if (widget.roleName == 'Teacher' && _selectedIndex == 4) {
      content = const TeacherScheduleScreen();
    } else if (widget.roleName == 'Teacher' && _selectedIndex == 5) {
      content = const StudentProfileScreen();
    } else if (widget.roleName == 'Student' && _selectedIndex == 0) {
      content = StudentDashboardScreen(
        onOpenAttendance: () {
          _selectDestination(1);
        },
        onOpenMarks: () {
          _selectDestination(2);
        },
        onOpenSchedule: () {
          _selectDestination(3);
        },
      );
    } else if (widget.roleName == 'Student' && _selectedIndex == 1) {
      content = const StudentAttendanceScreen();
    } else if (widget.roleName == 'Student' && _selectedIndex == 2) {
      content = const StudentMarksScreen();
    } else if (widget.roleName == 'Student' && _selectedIndex == 3) {
      content = const StudentScheduleScreen();
    } else if (widget.roleName == 'Student' && _selectedIndex == 4) {
      content = const StudentProfileScreen();
    } else {
      content = _ModulePlaceholder(
        roleName: widget.roleName,
        destination: destination,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.roleName} Workspace'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              final profileIndex = widget.destinations.indexWhere(
                (destination) => destination.label == 'Profile',
              );

              if (profileIndex >= 0) {
                _selectDestination(profileIndex);
              }
            },
            icon: const CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.informationBackground,
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ),
          if (widget.onSignOut != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Sign out',
                onPressed: _isSigningOut ? null : _signOut,
                icon: _isSigningOut
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
              ),
            ),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: AppColors.surface,
                  destinations: widget.destinations.map((item) {
                    return NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    );
                  }).toList(),
                ),
                const VerticalDivider(),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: widget.destinations.map((item) {
                return NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                );
              }).toList(),
            ),
    );
  }

  void _selectDestination(int index) {
    if (index < 0 || index >= widget.destinations.length) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _signOut() async {
    final signOut = widget.onSignOut;

    if (signOut == null || _isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await signOut();
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }
}

class _ModulePlaceholder extends StatelessWidget {
  final String roleName;
  final WorkspaceDestination destination;

  const _ModulePlaceholder({required this.roleName, required this.destination});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                destination.label,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                destination.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.extraLarge),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.extraLarge),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.informationBackground,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                      child: Icon(
                        destination.selectedIcon,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Text(
                      '$roleName ${destination.label}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text(
                      'This module is ready for its complete UI design.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
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
  }
}

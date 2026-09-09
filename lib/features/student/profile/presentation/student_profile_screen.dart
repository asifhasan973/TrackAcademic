import 'package:flutter/material.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  static const _authService = AuthService();

  late Future<AppUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _profileFuture = _authService.loadCurrentProfile();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUserProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _ProfileLoadError(
            message:
                snapshot.error?.toString() ??
                'Your profile could not be loaded.',
            onRetry: () {
              setState(_reload);
            },
          );
        }

        return _buildProfile(snapshot.data!);
      },
    );
  }

  Widget _buildProfile(AppUserProfile profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.large),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: AppSpacing.small),
                        Text(
                          'Your Trackademic account information.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _editProfile(profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.large),
              _ProfileSummaryCard(profile: profile),
              const SizedBox(height: AppSpacing.large),
              _buildInformationSection(profile),
              const SizedBox(height: AppSpacing.large),
              const _PrivacyCard(),
              const SizedBox(height: AppSpacing.large),
              _AccountSecurityCard(
                profile: profile,
                onChangePassword: () => _sendPasswordReset(profile.email),
                onSignOut: _showSignOutDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInformationSection(AppUserProfile profile) {
    final personal = _SectionCard(
      title: 'Account information',
      subtitle: 'Information stored in your Trackademic account.',
      icon: Icons.person_outline_rounded,
      children: [
        _InformationRow(
          icon: Icons.badge_outlined,
          label: 'Full name',
          value: _value(profile.displayName),
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: _value(profile.email),
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.numbers_rounded,
          label: 'Institution ID',
          value: _value(profile.institutionId),
        ),
      ],
    );

    final academic = _SectionCard(
      title: 'Academic information',
      subtitle: 'Optional information about your academic identity.',
      icon: Icons.school_outlined,
      children: [
        _InformationRow(
          icon: Icons.apartment_rounded,
          label: 'Department',
          value: _value(profile.department),
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.groups_rounded,
          label: 'Batch',
          value: _value(profile.batch),
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.group_outlined,
          label: 'Section',
          value: _value(profile.section),
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.calendar_today_outlined,
          label: 'Semester',
          value: _value(profile.semester),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: personal),
              const SizedBox(width: AppSpacing.regular),
              Expanded(child: academic),
            ],
          );
        }

        return Column(
          children: [
            personal,
            const SizedBox(height: AppSpacing.regular),
            academic,
          ],
        );
      },
    );
  }

  String _value(String? value) {
    final trimmed = value?.trim() ?? '';

    return trimmed.isEmpty ? 'Not provided' : trimmed;
  }

  Future<void> _editProfile(AppUserProfile profile) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _EditProfileDialog(profile: profile);
      },
    );

    if (updated == true && mounted) {
      setState(_reload);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    try {
      await _authService.sendPasswordReset(email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset instructions sent to $email.')),
      );
    } on AuthServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showSignOutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.logout_rounded,
            color: AppColors.warning,
            size: 40,
          ),
          title: const Text('Sign out?'),
          content: const Text(
            'Are you sure you want to sign out of Trackademic?',
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
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _authService.signOut();
    }
  }
}

class _EditProfileDialog extends StatefulWidget {
  final AppUserProfile profile;

  const _EditProfileDialog({required this.profile});

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  static const _authService = AuthService();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _departmentController;
  late final TextEditingController _batchController;
  late final TextEditingController _sectionController;
  late final TextEditingController _semesterController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.profile.displayName);

    _departmentController = TextEditingController(
      text: widget.profile.department ?? '',
    );

    _batchController = TextEditingController(text: widget.profile.batch ?? '');

    _sectionController = TextEditingController(
      text: widget.profile.section ?? '',
    );

    _semesterController = TextEditingController(
      text: widget.profile.semester ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _departmentController.dispose();
    _batchController.dispose();
    _sectionController.dispose();
    _semesterController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (value) {
                    final text = value?.trim() ?? '';

                    if (text.length < 2) {
                      return 'Enter your full name.';
                    }

                    if (text.length > 80) {
                      return 'Name is too long.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  initialValue: widget.profile.email,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText:
                        'Email changes require a separate verification flow.',
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  initialValue: widget.profile.institutionId,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Institution ID',
                    helperText:
                        'Institution ID cannot be changed from your profile.',
                  ),
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
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.pop(context, false);
                },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _authService.updateProfile(
        displayName: _nameController.text,
        department: _departmentController.text,
        batch: _batchController.text,
        section: _sectionController.text,
        semester: _semesterController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } on AuthServiceException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  final AppUserProfile profile;

  const _ProfileSummaryCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (profile.department?.trim().isNotEmpty == true)
        profile.department!.trim(),
      if (profile.batch?.trim().isNotEmpty == true) profile.batch!.trim(),
      if (profile.section?.trim().isNotEmpty == true) profile.section!.trim(),
      if (profile.semester?.trim().isNotEmpty == true) profile.semester!.trim(),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: AppColors.informationBackground,
              borderRadius: BorderRadius.circular(AppRadius.large),
            ),
            child: Center(
              child: Text(
                _initials(profile.displayName),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.large),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName.trim().isEmpty
                      ? 'Trackademic user'
                      : profile.displayName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.extraSmall),
                Text(
                  'Institution ID: ${profile.institutionId}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.medium),
                if (labels.isEmpty)
                  const Text(
                    'Academic details have not been added yet.',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.small,
                    runSpacing: AppSpacing.small,
                    children: [
                      for (final label in labels) _ProfileLabel(text: label),
                    ],
                  ),
              ],
            ),
          ),
          if (const AuthService().currentUser?.emailVerified == true)
            const Tooltip(
              message: 'Email verified',
              child: Icon(
                Icons.verified_rounded,
                color: AppColors.success,
                size: 30,
              ),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'U';
    }

    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return const _SectionCard(
      title: 'Privacy and record access',
      subtitle: 'Course data is protected by course membership and ownership.',
      icon: Icons.privacy_tip_outlined,
      children: [
        _ProtectedRecordTile(
          icon: Icons.fact_check_outlined,
          title: 'Attendance records',
          access: 'Available to you and the owner of the relevant course',
        ),
        Divider(),
        _ProtectedRecordTile(
          icon: Icons.analytics_outlined,
          title: 'Marks and results',
          access: 'Available to you and the owner of the relevant course',
        ),
        Divider(),
        _ProtectedRecordTile(
          icon: Icons.location_on_outlined,
          title: 'Location',
          access:
              'Used only when an attendance session requires GPS verification',
        ),
      ],
    );
  }
}

class _AccountSecurityCard extends StatelessWidget {
  final AppUserProfile profile;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;

  const _AccountSecurityCard({
    required this.profile,
    required this.onChangePassword,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final user = const AuthService().currentUser;

    return _SectionCard(
      title: 'Account security',
      subtitle: 'Firebase Authentication account status.',
      icon: Icons.security_rounded,
      children: [
        _InformationRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: profile.email,
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.verified_user_outlined,
          label: 'Email verification',
          value: user?.emailVerified == true ? 'Verified' : 'Not verified',
        ),
        const SizedBox(height: AppSpacing.medium),
        _InformationRow(
          icon: Icons.login_rounded,
          label: 'Last sign-in',
          value: _formatDateTime(user?.metadata.lastSignInTime),
        ),
        const SizedBox(height: AppSpacing.large),
        Wrap(
          spacing: AppSpacing.medium,
          runSpacing: AppSpacing.medium,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onChangePassword,
              icon: const Icon(Icons.password_rounded),
              label: const Text('Reset password'),
            ),
            FilledButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.informationBackground,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.medium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.large),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 20),
        const SizedBox(width: AppSpacing.medium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: AppSpacing.extraSmall),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProtectedRecordTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String access;

  const _ProtectedRecordTile({
    required this.icon,
    required this.title,
    required this.access,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  access,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.small),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.medium,
              vertical: AppSpacing.extraSmall,
            ),
            decoration: BoxDecoration(
              color: AppColors.successBackground,
              borderRadius: BorderRadius.circular(AppRadius.circular),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: AppColors.success, size: 14),
                SizedBox(width: AppSpacing.extraSmall),
                Text(
                  'Protected',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLabel extends StatelessWidget {
  final String text;

  const _ProfileLabel({required this.text});

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
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfileLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.medium),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.large),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

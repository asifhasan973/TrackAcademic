import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trackademic/core/models/user_role.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/services/class_reminder_service.dart';
import 'package:trackademic/core/services/push_notification_service.dart';
import 'package:trackademic/core/services/teacher_academic_service.dart';
import 'package:trackademic/features/authentication/presentation/sign_in_screen.dart';
import 'package:trackademic/features/ui_preview/presentation/role_workspace_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError) {
          return _AuthenticationErrorScreen(error: snapshot.error);
        }

        final user = snapshot.data;

        if (user == null) {
          return const SignInScreen();
        }

        if (!user.emailVerified) {
          return const _EmailVerificationScreen();
        }

        return _WorkspaceLoader(key: ValueKey(user.uid));
      },
    );
  }
}

class _WorkspaceLoader extends StatefulWidget {
  const _WorkspaceLoader({super.key});

  @override
  State<_WorkspaceLoader> createState() => _WorkspaceLoaderState();
}

class _WorkspaceLoaderState extends State<_WorkspaceLoader> {
  static const _authService = AuthService();
  static const _teacherAcademicService = TeacherAcademicService();

  late final Future<UserRole> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = _resolveRole();
  }

  Future<UserRole> _resolveRole() async {
    final profile = await _authService.loadCurrentProfile();

    // Request notification permission and register device token for push notifications
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      PushNotificationService().requestPermission().then((granted) {
        if (granted) {
          PushNotificationService().registerUserDevice(uid);
        }
      }).catchError((e) {
        debugPrint('[AuthGate] FCM token registration error: $e');
      });

      // Signal ready to process pending push targets
      if (mounted) {
        PushNotificationService().onAppReady(context, profile);
      }

      // Start zero-cost device-local class timetable reminders
      ClassReminderService().startScheduleSync(uid, profile.role ?? 'student');
    }

    final roleString = profile.role?.trim().toLowerCase();
    if (roleString == 'teacher') {
      return UserRole.teacher;
    } else if (roleString == 'student') {
      return UserRole.student;
    }

    // Compatibility fallback for legacy profile without role:
    try {
      final courses = await _teacherAcademicService.loadMyCourses();
      if (courses.isNotEmpty) {
        return UserRole.teacher;
      }
    } catch (_) {}

    return UserRole.student;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserRole>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _ProfileErrorScreen(error: snapshot.error);
        }

        return RoleWorkspaceScreen(
          role: snapshot.data!,
          onSignOut: _authService.signOut,
        );
      },
    );
  }
}

class _EmailVerificationScreen extends StatefulWidget {
  const _EmailVerificationScreen();

  @override
  State<_EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<_EmailVerificationScreen>
    with WidgetsBindingObserver {
  static const _authService = AuthService();

  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isWorking) {
      // User may have just returned to the app after clicking the email link
      _checkVerification(silent: true);
    }
  }

  Future<void> _resendEmail() async {
    await _performAction(() async {
      await _authService.resendVerificationEmail();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
    });
  }

  Future<void> _checkVerification({bool silent = false}) async {
    await _performAction(() async {
      final verified = await _authService.refreshEmailVerification();

      if (!mounted) {
        return;
      }

      if (!verified && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email is not verified yet. Open the verification link first.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _performAction(Future<void> Function() action) async {
    if (_isWorking) {
      return;
    }

    setState(() {
      _isWorking = true;
    });

    try {
      await action();
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
          _isWorking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _authService.currentUser?.email ?? 'your email';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _isWorking
              ? null
              : () {
                  _authService.signOut();
                },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Verify email'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 72,
                    color: Color(0xFF3454D1),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Check your inbox',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to $email. '
                    'Open the link, then return here.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isWorking ? null : _checkVerification,
                      icon: _isWorking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('I verified my email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isWorking ? null : _resendEmail,
                    child: const Text('Resend verification email'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AuthenticationErrorScreen extends StatelessWidget {
  final Object? error;

  const _AuthenticationErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Authentication failed:\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ProfileErrorScreen extends StatelessWidget {
  final Object? error;

  const _ProfileErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error?.toString() ??
                    'Your account profile could not be loaded.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  const AuthService().signOut();
                },
                child: const Text('Return to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

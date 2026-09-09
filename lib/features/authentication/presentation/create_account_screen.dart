import 'package:flutter/material.dart';
import 'package:trackademic/features/authentication/presentation/sign_in_screen.dart';
import 'package:trackademic/core/services/auth_service.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _authService = AuthService();

  bool _isSubmitting = false;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _institutionIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _hidePassword = true;
  bool _hideConfirmedPassword = true;

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _institutionIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) {
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _authService.register(
        displayName: _nameController.text,
        email: _emailController.text,
        institutionId: _institutionIdController.text,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
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
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FF),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Create account',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF17203B),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3454D1), Color(0xFF6D5CE7)],
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 26),

                    const Text(
                      'Join Trackademic',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: Color(0xFF17203B),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Create an account using your institutional '
                      'information. Your role will be verified automatically.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xFF68728B),
                      ),
                    ),

                    const SizedBox(height: 32),

                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: _inputDecoration(
                        label: 'Full name',
                        hint: 'Enter your full name',
                        icon: Icons.person_outline_rounded,
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';

                        if (name.isEmpty) {
                          return 'Please enter your full name.';
                        }

                        if (name.length < 3) {
                          return 'Name must contain at least 3 characters.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: _inputDecoration(
                        label: 'Institutional email',
                        hint: 'student@university.edu',
                        icon: Icons.email_outlined,
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return 'Please enter your email address.';
                        }

                        if (!_isValidEmail(email)) {
                          return 'Please enter a valid email address.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _institutionIdController,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        label: 'Institution ID',
                        hint: 'Enter your student or employee ID',
                        icon: Icons.badge_outlined,
                      ),
                      validator: (value) {
                        final institutionId = value?.trim() ?? '';

                        if (institutionId.isEmpty) {
                          return 'Please enter your institution ID.';
                        }

                        if (institutionId.length < 3) {
                          return 'Please enter a valid institution ID.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: _inputDecoration(
                        label: 'Password',
                        hint: 'At least 8 characters',
                        icon: Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';

                        if (password.isEmpty) {
                          return 'Please create a password.';
                        }

                        if (password.length < 8) {
                          return 'Password must contain at least 8 characters.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _hideConfirmedPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_isSubmitting) {
                          _submitForm();
                        }
                      },
                      decoration: _inputDecoration(
                        label: 'Confirm password',
                        hint: 'Enter your password again',
                        icon: Icons.lock_reset_rounded,
                        suffixIcon: IconButton(
                          tooltip: _hideConfirmedPassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () {
                            setState(() {
                              _hideConfirmedPassword = !_hideConfirmedPassword;
                            });
                          },
                          icon: Icon(
                            _hideConfirmedPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password.';
                        }

                        if (value != _passwordController.text) {
                          return 'The passwords do not match.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 26),

                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submitForm,
                        icon: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          _isSubmitting
                              ? 'Creating account...'
                              : 'Create account',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF0FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD5DFFF)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            color: Color(0xFF3454D1),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Teacher and student permissions cannot be '
                              'selected manually. They will be assigned '
                              'using verified institutional records.',
                              style: TextStyle(
                                height: 1.45,
                                color: Color(0xFF435175),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account?',
                          style: TextStyle(color: Color(0xFF68728B)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (context) => const SignInScreen(),
                              ),
                            );
                          },
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

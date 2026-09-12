import 'package:flutter/material.dart';
import 'package:trackademic/core/services/auth_service.dart';
import 'package:trackademic/core/widgets/brand_mark.dart';
import 'package:trackademic/features/authentication/presentation/create_account_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _authService = AuthService();

  bool _isSubmitting = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _hidePassword = true;

  bool _isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
      await _authService.signIn(
        email: _emailController.text,
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

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your valid email address first.')),
      );
      return;
    }

    try {
      await _authService.sendPasswordReset(email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password-reset email sent.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FF),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Sign in',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF17203B),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 72, borderRadius: 22),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: Color(0xFF17203B),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Sign in using your registered TrackAcademic account. '
                      'Your teacher or student role will be verified automatically.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xFF68728B),
                      ),
                    ),

                    const SizedBox(height: 34),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: 'Email address',
                        hintText: 'name@example.com',
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) {
                        if (!_isSubmitting) {
                          _submitForm();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';

                        if (password.isEmpty) {
                          return 'Please enter your password.';
                        }

                        if (password.length < 8) {
                          return 'Password must contain at least 8 characters.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _sendPasswordReset,
                        child: const Text('Forgot password?'),
                      ),
                    ),

                    const SizedBox(height: 12),

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
                            : const Icon(Icons.login_rounded),
                        label: Text(
                          _isSubmitting ? 'Signing in...' : 'Sign in securely',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

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
                            Icons.verified_user_outlined,
                            color: Color(0xFF3454D1),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your role and access permissions will be '
                              'verified securely after you sign in.',
                              style: TextStyle(
                                height: 1.45,
                                color: Color(0xFF435175),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Color(0xFF68728B)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    const CreateAccountScreen(),
                              ),
                            );
                          },
                          child: const Text('Create account'),
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
}

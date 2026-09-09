import 'package:flutter/material.dart';
import '../../authentication/presentation/sign_in_screen.dart';
import '../../authentication/presentation/create_account_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 620;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9FF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: isCompact ? 16 : 28,

        // Application logo and name
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3454D1), Color(0xFF6D5CE7)],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.school_rounded, color: Colors.white),
            ),
            const SizedBox(width: 11),
            Text(
              'Trackademic',
              style: TextStyle(
                fontSize: isCompact ? 18 : 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),

        // Authentication actions
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const SignInScreen(),
                ),
              );
            },
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(isCompact ? 'Login' : 'Sign in'),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isCompact ? 2 : 8,
              right: isCompact ? 8 : 20,
            ),
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const CreateAccountScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 14 : 20,
                  vertical: 12,
                ),
              ),
              child: Text(isCompact ? 'Join' : 'Create account'),
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7F9FF), Color(0xFFEEF2FF), Color(0xFFF9FBFF)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 46, 24, 56),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1150),
                child: Column(
                  children: [
                    const _HeroSection(),
                    const SizedBox(height: 64),
                    const _FeatureSection(),
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

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 880;

        const message = _HeroMessage();
        const attendancePreview = _AttendancePreview();

        if (isWideScreen) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 11, child: message),
              SizedBox(width: 54),
              Expanded(flex: 9, child: attendancePreview),
            ],
          );
        }

        return const Column(
          children: [message, SizedBox(height: 42), attendancePreview],
        );
      },
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE7ECFF),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: const Color(0xFFD3DCFF)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 18,
                color: Color(0xFF3454D1),
              ),
              SizedBox(width: 7),
              Text(
                'GPS-secured attendance',
                style: TextStyle(
                  color: Color(0xFF2947B7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Attendance that works\nonly where the class is.',
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -1.3,
            color: const Color(0xFF17203B),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Trackademic combines secure classroom attendance, '
          'academic records, CT marks, attendance marks, and '
          'class schedules in one organized platform.',
          style: textTheme.titleMedium?.copyWith(
            height: 1.6,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF5D6680),
          ),
        ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _BenefitChip(
              icon: Icons.timer_outlined,
              label: 'Temporary passcode',
            ),
            _BenefitChip(
              icon: Icons.radar_rounded,
              label: 'Radius verification',
            ),
            _BenefitChip(
              icon: Icons.lock_outline_rounded,
              label: 'Private records',
            ),
          ],
        ),
      ],
    );
  }
}

class _BenefitChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BenefitChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE1E6F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF3454D1)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF3B455F),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendancePreview extends StatelessWidget {
  const _AttendancePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7184F4), Color(0xFF9A7BEA)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3454D1).withValues(alpha: 0.18),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _PreviewIcon(),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Attendance Session',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17203B),
                    ),
                  ),
                ),
                _LiveBadge(),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'CSE-300',
              style: TextStyle(
                color: Color(0xFF3454D1),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Software Development Project',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17203B),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFFDDE6FF),
                    child: Icon(
                      Icons.my_location_rounded,
                      color: Color(0xFF3454D1),
                    ),
                  ),
                  SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inside attendance area',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF263252),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Within the teacher-defined 50 m radius',
                          style: TextStyle(
                            color: Color(0xFF68728B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.verified_rounded, color: Color(0xFF179B69)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SessionInformationRow(
              icon: Icons.password_rounded,
              title: 'Session passcode',
              value: '5821',
            ),
            const SizedBox(height: 14),
            const _SessionInformationRow(
              icon: Icons.timer_outlined,
              title: 'Time remaining',
              value: '00:47',
            ),
            const SizedBox(height: 14),
            const _SessionInformationRow(
              icon: Icons.gps_fixed_rounded,
              title: 'Location status',
              value: 'Verified',
              positive: true,
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8F2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFC8EBDD)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF16865D)),
                  SizedBox(width: 9),
                  Text(
                    'Ready to mark attendance',
                    style: TextStyle(
                      color: Color(0xFF13704F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFE7ECFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.how_to_reg_rounded, color: Color(0xFF3454D1)),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEC),
        borderRadius: BorderRadius.circular(50),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: Color(0xFFE64C4C)),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFFC63838),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionInformationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool positive;

  const _SessionInformationRow({
    required this.icon,
    required this.title,
    required this.value,
    this.positive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: const Color(0xFF6D7690)),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6D7690),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: positive ? const Color(0xFF16865D) : const Color(0xFF263252),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Everything important, in one place',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.7,
            color: Color(0xFF17203B),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Built for both teachers and students.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Color(0xFF68728B)),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;

            final double cardWidth;

            if (availableWidth >= 1000) {
              cardWidth = (availableWidth - 32) / 3;
            } else if (availableWidth >= 650) {
              cardWidth = (availableWidth - 16) / 2;
            } else {
              cardWidth = availableWidth;
            }

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: const _FeatureCard(
                    icon: Icons.location_on_rounded,
                    title: 'Secure attendance',
                    description:
                        'Temporary passcodes, session timing, '
                        'and GPS-radius verification.',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const _FeatureCard(
                    icon: Icons.analytics_rounded,
                    title: 'Marks and progress',
                    description:
                        'Track attendance percentage, attendance '
                        'marks, and Class Test results.',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const _FeatureCard(
                    icon: Icons.calendar_month_rounded,
                    title: 'Schedules and privacy',
                    description:
                        'View updated class schedules while keeping '
                        'student academic records private.',
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 190),
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E8F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE7ECFF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: const Color(0xFF3454D1)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF17203B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(height: 1.5, color: Color(0xFF68728B)),
          ),
        ],
      ),
    );
  }
}

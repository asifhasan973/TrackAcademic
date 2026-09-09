import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackademic/features/welcome/presentation/welcome_screen.dart';

void main() {
  testWidgets('Trackademic welcome screen displays correctly', (
    WidgetTester tester,
  ) async {
    // Build the Trackademic application.
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    // Verify important welcome-screen content.
    expect(find.text('Trackademic'), findsOneWidget);

    expect(
      find.text('Attendance that works\nonly where the class is.'),
      findsOneWidget,
    );

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });
}

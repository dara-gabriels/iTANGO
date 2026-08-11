// test/widgets/itango_gradient_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itango/core/theme/itango_theme.dart';

void main() {
  testWidgets('renders its label and fires onPressed exactly once per tap', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItangoGradientButton(
            label: 'Continue',
            onPressed: () => tapCount++,
          ),
        ),
      ),
    );

    expect(find.text('Continue'), findsOneWidget);
    expect(tapCount, 0);

    await tester.tap(find.byType(ItangoGradientButton));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('renders an icon when one is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItangoGradientButton(label: 'With icon', icon: Icons.check, onPressed: () {}),
        ),
      ),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('omits the icon when none is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItangoGradientButton(label: 'Without icon', onPressed: () {}),
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('applies the brand primary gradient, not just any decoration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItangoGradientButton(label: 'Get Tickets', onPressed: () {}),
        ),
      ),
    );

    final containerFinder = find.descendant(
      of: find.byType(ItangoGradientButton),
      matching: find.byType(Container),
    );
    final container = tester.widget<Container>(containerFinder.first);
    final decoration = container.decoration as BoxDecoration;

    // Asserts the actual brand gradient is applied, not just "some
    // decoration exists" — a button with a plain color fill would pass a
    // weaker assertion but fail the actual design requirement.
    expect(decoration.gradient, ItangoGradients.primaryCta);
  });
}

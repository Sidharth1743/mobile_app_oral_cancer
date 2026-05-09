import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/main.dart';

void main() {
  testWidgets('intake screen renders required workflow fields', (tester) async {
    await tester.pumpWidget(const OralCancerApp());
    await tester.pumpAndSettle();

    expect(find.text('Screening intake'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Village / area'), findsOneWidget);
    expect(find.text('State'), findsOneWidget);
    expect(find.text('District'), findsOneWidget);
    expect(find.text('Tamil Nadu'), findsOneWidget);
    expect(find.text('Date of birth'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Tobacco brand'), findsOneWidget);
    expect(find.text('Chews per day'), findsOneWidget);
    expect(find.text('Years used'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('DOB picker stores selected valid date', (tester) async {
    await tester.pumpWidget(const OralCancerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dob-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('1985-01-01'), findsOneWidget);
  });
}

// Basic smoke test: verifies the app boots and shows the splash/auth UI
// without throwing.

import 'package:flutter_test/flutter_test.dart';

import 'package:email_app/main.dart';

void main() {
  testWidgets('App boots and renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const EmailApp());
    await tester.pump();

    expect(find.text('Email'), findsWidgets);
  });
}

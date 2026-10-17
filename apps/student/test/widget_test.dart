import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securequiz_student/main.dart';

void main() {
  testWidgets('missing configuration gives a usable explanation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            StudentHome(problem: 'Ask your teacher for the configured APK.')));
    expect(find.text('SecureQuiz'), findsOneWidget);
    expect(
        find.text('Ask your teacher for the configured APK.'), findsOneWidget);
  });
}

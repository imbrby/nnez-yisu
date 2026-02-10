import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnez_yisu/main.dart';

void main() {
  testWidgets('app renders on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const CanteenApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);

    // Drain the 20s bootstrap timeout timer
    await tester.pump(const Duration(seconds: 21));
  });
}

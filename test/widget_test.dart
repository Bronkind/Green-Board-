import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_board/main.dart';

void main() {
  testWidgets('Green Board smoke test', (WidgetTester tester) async {
    // Set test screen size to avoid overflow during test rendering
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;

    // Build our app and trigger a frame.
    await tester.pumpWidget(const GreenBoardApp());
    await tester.pumpAndSettle();

    // Verify that GREEN BOARD header exists.
    expect(find.text('GREEN BOARD'), findsOneWidget);

    // Reset view size after test
    addTearDown(tester.view.resetPhysicalSize);
  });
}
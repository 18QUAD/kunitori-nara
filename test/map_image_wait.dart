import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Map controls now wait for both image workers and image retirement.
Future<void> waitForMapImages(WidgetTester tester) async {
  bool ready() => tester
      .widgetList<IconButton>(find.byType(IconButton))
      .any(
        (button) =>
            (button.tooltip?.startsWith('起伏・市街地') ?? false) &&
            button.onPressed != null,
      );
  for (var frame = 0; frame < 300 && !ready(); frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Map image work must finish and unlock controls',
  );
}

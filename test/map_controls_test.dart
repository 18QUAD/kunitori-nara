import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_controls.dart';

void main() {
  for (final name in ['map-home', 'map-up']) {
    testWidgets('$name rejects taps during image work and resumes afterwards', (
      tester,
    ) async {
      var busy = false;
      var visits = 0;
      final control = IconButton.filledTonal(
        key: Key(name),
        tooltip: '本拠地へ',
        onPressed: () => visits++,
        icon: const Icon(Icons.home_outlined),
      );
      Future<void> paint() => tester.pumpWidget(
        MaterialApp(home: lockMapNavigationControl(control, () => busy)),
      );
      await paint();
      await tester.tap(find.byKey(Key(name)));
      expect(visits, 1);
      // Work starts before the next disabled frame can be shown.
      busy = true;
      await tester.tap(find.byKey(Key(name)));
      expect(visits, 1);
      await paint();
      expect(
        tester.widget<IconButton>(find.byKey(Key(name))).onPressed,
        isNull,
      );
      busy = false;
      await paint();
      await tester.tap(find.byKey(Key(name)));
      expect(visits, 2);
    });
  }
}

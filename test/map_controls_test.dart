import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_controls.dart';

void main() {
  testWidgets('home rejects taps during image work and resumes afterwards', (
    tester,
  ) async {
    var busy = false;
    var visits = 0;
    final control = IconButton.filledTonal(
      key: const Key('map-home'),
      tooltip: '本拠地へ',
      onPressed: () => visits++,
      icon: const Icon(Icons.home_outlined),
    );
    Future<void> paint() => tester.pumpWidget(
      MaterialApp(home: lockMapHomeControl(control, () => busy)),
    );
    await paint();
    await tester.tap(find.byKey(const Key('map-home')));
    expect(visits, 1);
    // Work starts before the next disabled frame can be shown.
    busy = true;
    await tester.tap(find.byKey(const Key('map-home')));
    expect(visits, 1);
    await paint();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('map-home'))).onPressed,
      isNull,
    );
    busy = false;
    await paint();
    await tester.tap(find.byKey(const Key('map-home')));
    expect(visits, 2);
  });
}

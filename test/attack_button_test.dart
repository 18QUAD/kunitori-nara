import 'dart:ui' show SemanticsAction;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/attack_button.dart';

void main() {
  testWidgets('each contact counts on down, with no release or hold repeats', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            height: 150,
            child: protectAttackTap(
              onPressed: () => count++,
              child: FilledButton(
                onPressed: () => count++,
                child: const Text('進軍'),
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(FilledButton));
    final left = await tester.startGesture(
      center - const Offset(60, 0),
      pointer: 1,
    );
    expect(count, 1);
    final right = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    expect(
      count,
      2,
      reason: 'The second finger counts before either is lifted',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    await left.moveBy(const Offset(0, 30));
    await left.up();
    await right.cancel();
    await tester.pump();
    expect(count, 2, reason: 'Moves, releases and cancellation add nothing');
    for (var i = 0; i < 50; i++) {
      final a = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 3,
      );
      final b = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 4,
      );
      await a.up();
      await b.up();
    }
    expect(count, 102);
    await tester.pumpAndSettle();
    expect(count, 102);
    final secondary = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
      pointer: 5,
    );
    await secondary.up();
    expect(count, 102);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count, 103, reason: 'Keyboard activation is still one action');
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('進軍'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(count, 104, reason: 'Accessible activation remains available');
    handle.dispose();
  });

  testWidgets('disabled contacts and accessible activation remain disabled', (
    tester,
  ) async {
    var count = 0;
    Widget button(bool enabled) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 350,
          height: 150,
          child: protectAttackTap(
            onPressed: enabled ? () => count++ : null,
            child: FilledButton(
              onPressed: enabled ? () => count++ : null,
              child: const Text('進軍不可'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(button(true));
    final held = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('attack'))),
    );
    expect(count, 1);
    await tester.pumpWidget(button(false));
    await held.up();
    await tester.tap(find.byKey(const Key('attack')));
    await tester.pump();
    expect(count, 1);
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('進軍不可'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });
}

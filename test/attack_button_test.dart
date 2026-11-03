import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/attack_button_stub.dart';
import 'package:kunitori/action_choices.dart';

void main() {
  testWidgets('portrait halves count simultaneous touches independently', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 120,
            child: protectAttackTap(
              onPressed: () => count++,
              child: FilledButton(onPressed: () {}, child: const Text('タップ')),
            ),
          ),
        ),
      ),
    );
    final left = await tester.startGesture(const Offset(60, 60), pointer: 1);
    final right = await tester.startGesture(const Offset(300, 60), pointer: 2);
    expect(count, 2);
    await left.up();
    await right.up();
    expect(count, 2, reason: 'Release must not double count');
    await tester.tapAt(const Offset(300, 60));
    expect(count, 3);
  });
  testWidgets(
    'landscape accepts multiple concurrent contacts and cancels cleanly',
    (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionChoiceRegion(
              right: true,
              child: SizedBox(
                width: 200,
                height: 120,
                child: protectAttackTap(
                  onPressed: () => count++,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
      final a = await tester.startGesture(
        const Offset(30, 30),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final b = await tester.startGesture(
        const Offset(90, 30),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      expect(count, 2);
      await a.cancel();
      await b.up();
      await tester.tapAt(const Offset(90, 30));
      expect(count, 3);
    },
  );
}

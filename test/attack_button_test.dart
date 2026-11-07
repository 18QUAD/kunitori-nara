import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/attack_button_stub.dart';
import 'package:kunitori/action_choices.dart';

void main() {
  for (final size in [const Size(390, 200), const Size(320, 64)]) {
    testWidgets('portrait targets stay separate within $size', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: protectAttackTap(
                  onPressed: () => count++,
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('タップ'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final targets = find.byKey(const Key('attack'));
      final left = tester.getRect(targets.at(0));
      final right = tester.getRect(targets.at(1));
      expect(right.left - left.right, 8);
      expect(left.height, lessThanOrEqualTo(90));
      expect(left.height, lessThanOrEqualTo(size.height));
      expect(right.height, left.height);
      expect(left.width, right.width);
      await tester.tapAt(Offset(size.width / 2, left.center.dy));
      expect(count, 0, reason: 'The visible gap must not accept attack taps');
      if (size.height > 90) {
        await tester.tapAt(Offset(left.center.dx, 100));
        expect(count, 0, reason: 'The empty area below is not a tap target');
      }
      final a = await tester.startGesture(left.center, pointer: 1);
      final b = await tester.startGesture(right.center, pointer: 2);
      expect(count, 2);
      await a.up();
      await b.up();
      expect(count, 2);
      expect(tester.takeException(), isNull);
    });
  }

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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/tip_appearance.dart';
import 'package:kunitori/tip_character.dart';

void main() {
  Widget scene(
    TipAppearance a, {
    Object speech = 'one',
    DateTime? next,
    bool reduced = false,
    bool active = true,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: active,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: TipCharacterView(
              appearance: a,
              speechKey: speech,
              nextSpeechAt: next,
            ),
          ),
        ),
      ),
    ),
  );

  for (final character in TipCharacter.values) {
    testWidgets(
      '${character.name} lip sync repeats and stops one second before next speech',
      (tester) async {
        final a = TipAppearance(character: character, blinkEnabled: false);
        final next = DateTime.now().add(const Duration(seconds: 5));
        bool closed() =>
            character == TipCharacter.guide
                ? find
                    .byKey(const Key('guide-closed-mouth'))
                    .evaluate()
                    .isNotEmpty
                : (tester
                            .widget<CustomPaint>(
                              find.byKey(const Key('deer-face-parts')),
                            )
                            .painter
                        as DeerCharacterPainter)
                    .mouthClosed;
        await tester.pumpWidget(scene(a, next: next));
        final initial = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !initial);
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), initial);
        await tester.pump(const Duration(milliseconds: 3800));
        expect(closed(), isTrue);
        await tester.pump(const Duration(seconds: 2));
        expect(closed(), isTrue);
        await tester.pumpWidget(
          scene(
            a,
            speech: 'two',
            next: DateTime.now().add(const Duration(seconds: 5)),
          ),
        );
        final restarted = closed();
        await tester.pump(const Duration(milliseconds: 180));
        expect(closed(), !restarted);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${character.name} blinks, then opens eyes; disabling animations cancels parts',
      (tester) async {
        final a = TipAppearance(character: character, lipSyncEnabled: false);
        bool closed() =>
            character == TipCharacter.guide
                ? find
                    .byKey(const Key('guide-closed-eyes'))
                    .evaluate()
                    .isNotEmpty
                : (tester
                            .widget<CustomPaint>(
                              find.byKey(const Key('deer-face-parts')),
                            )
                            .painter
                        as DeerCharacterPainter)
                    .eyesClosed;
        await tester.pumpWidget(scene(a));
        var blinked = false;
        for (var i = 0; i < 610; i++) {
          if (i % 50 == 0) {
            await tester.pumpWidget(scene(a, speech: i));
          }
          await tester.pump(const Duration(milliseconds: 10));
          if (closed()) {
            blinked = true;
            break;
          }
        }
        expect(blinked, isTrue);
        await tester.pump(const Duration(milliseconds: 140));
        expect(closed(), isFalse);
        await tester.pumpWidget(
          scene(a.copyWith(blinkEnabled: false, lipSyncEnabled: false)),
        );
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(scene(a, reduced: true));
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(scene(a, active: false));
        await tester.pump(const Duration(seconds: 10));
        expect(closed(), isFalse);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}

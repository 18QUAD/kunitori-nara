import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/tap_progress.dart';

void main() {
  testWidgets(
    'new taps pulse, rapid taps restart, selection resets and reduced motion stays still',
    (tester) async {
      Widget scene(int taps, {String town = 'a', bool reduced = false}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                child: SizedBox(
                  width: 180,
                  child: TapProgress(
                    townId: town,
                    value: taps,
                    population: 12000,
                    tapCount: taps,
                  ),
                ),
              ),
            ),
          );
      double scale() =>
          tester
              .widget<ScaleTransition>(
                find.byKey(const Key('tap-progress-pulse')),
              )
              .scale
              .value;
      await tester.pumpWidget(scene(0));
      expect(scale(), 1);
      final style =
          DefaultTextStyle.of(
            tester.element(find.byKey(const Key('attack-progress'))),
          ).style;
      expect(style.fontSize, 22);
      expect(style.fontWeight, FontWeight.w900);
      final populationRect = tester.getRect(
        find.byKey(const Key('attack-population')),
      );
      await tester.pumpWidget(scene(1));
      await tester.pump(const Duration(milliseconds: 96));
      expect(scale(), closeTo(1.13, .001));
      expect(
        tester.getRect(find.byKey(const Key('attack-population'))),
        populationRect,
      );
      expect(
        tester.getRect(find.byKey(const Key('attack-progress'))).height,
        greaterThan(populationRect.height),
      );
      await tester.pumpWidget(scene(2));
      expect(scale(), 1);
      await tester.pump(const Duration(milliseconds: 96));
      expect(scale(), greaterThan(1.1));
      await tester.pump(const Duration(milliseconds: 144));
      expect(scale(), 1);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('/ 12,000'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('attack-population'))),
        populationRect,
      );
      await tester.pumpWidget(scene(2));
      await tester.pump(const Duration(milliseconds: 96));
      expect(scale(), 1);
      await tester.pumpWidget(scene(3));
      await tester.pump(const Duration(milliseconds: 96));
      await tester.pumpWidget(scene(3, town: 'b'));
      expect(scale(), 1);
      await tester.pumpWidget(scene(4, town: 'b', reduced: true));
      await tester.pump(const Duration(milliseconds: 96));
      expect(scale(), 1);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/tip_appearance.dart';

void main() {
  for (final legacy in [false, true]) {
    testWidgets(
      'restore tap height for ${legacy ? 'saved controls' : 'default'} tips',
      (tester) async {
        rootBundle.clear();
        SharedPreferences.setMockInitialValues({
          if (legacy)
            TipAppearanceStore.key: jsonEncode({
              'placement': 'controls',
              'size': 'large',
              'showTips': true,
            }),
        });
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const KunitoriApp());
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
          if (find.byKey(const Key('play-layout')).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
        final height =
            tester.getSize(find.byKey(const Key('play-layout'))).height;
        final formerMapHeight = math.min(
          height * .6 + 12,
          math.max(0, height - 168),
        );
        final formerTipHeight = math.min(
          (legacy ? TipSize.large : TipSize.standard).height,
          (height - formerMapHeight - 16) * .4,
        );
        final map = tester.getRect(find.byKey(const Key('fixed-region')));
        final action = tester.getRect(find.byKey(const Key('action-region')));
        expect(map.height, closeTo(formerMapHeight + formerTipHeight + 8, .01));
        expect(
          action.height - 16,
          closeTo(height - formerMapHeight - 16 - formerTipHeight - 8, .01),
        );
        expect(
          map.contains(
            tester.getRect(find.byKey(const Key('tips-region'))).center,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

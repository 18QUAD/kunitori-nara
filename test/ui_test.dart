import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/tip_appearance.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/game.dart' show number;
import 'package:kunitori/territory_map.dart';

void expectMapControlsInside(WidgetTester tester) {
  final map = tester.getRect(find.byType(TerritoryMap));
  for (final label in ['県全域を表示', '起伏・市街地・山名・川・池・湖を非表示', '拡大', '縮小']) {
    final control = tester.getRect(find.byTooltip(label));
    expect(map.contains(control.topLeft), isTrue, reason: label);
    expect(map.contains(control.bottomRight), isTrue, reason: label);
  }
  final ordered = [
    find.byKey(const Key('map-home')),
    find.byTooltip('拡大'),
    find.byTooltip('縮小'),
    find.byTooltip('県全域を表示'),
    find.byTooltip('起伏・市街地・山名・川・池・湖を非表示'),
  ];
  for (var i = 1; i < ordered.length; i++) {
    expect(
      tester.getRect(ordered[i]).top,
      greaterThan(tester.getRect(ordered[i - 1]).bottom),
    );
  }
  final compass = tester.getRect(find.byKey(const Key('map-compass')));
  expect(compass.topLeft, map.topLeft + const Offset(8, 8));
  final firstControl = tester.getRect(find.byKey(const Key('map-home')));
  expect(firstControl.top, greaterThanOrEqualTo(map.top + 4));
  expect(firstControl.top, lessThanOrEqualTo(map.top + 8));
  expect(find.byTooltip('市町村・町を探す'), findsNothing);
  final home = tester.getRect(find.byKey(const Key('map-home')));
  expect(map.contains(home.topLeft), isTrue);
  expect(map.contains(home.bottomRight), isTrue);
}

void expectCenteredOn(WidgetTester tester, String id) {
  final map = find.byType(TerritoryMap);
  final viewer = tester.widget<InteractiveViewer>(
    find.descendant(of: map, matching: find.byType(InteractiveViewer)),
  );
  final detector = viewer.child as GestureDetector;
  final canvas = detector.child as SizedBox;
  final dynamic painter = (canvas.child as CustomPaint).painter;
  final Rect bounds = painter.bounds[id] as Rect;
  final center = viewer.transformationController!.toScene(
    tester.getSize(map).center(Offset.zero),
  );
  expect(center.dx, closeTo(bounds.center.dx, 0.01));
  expect(center.dy, closeTo(bounds.center.dy, 0.01));
}

void main() {
  testWidgets('phone layout loads, search selects a home, campaign saves', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KunitoriApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('旅のはじまり').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('くにとり'), findsNothing);
    expect(find.text('地図'), findsNothing);
    expect(find.text('戦績'), findsNothing);
    expect(find.text('奈良県'), findsOneWidget);
    expect(find.text('領土'), findsNothing);
    expect(find.text('人口'), findsNothing);
    expect(find.text('面積'), findsNothing);
    final fixed = tester.getRect(find.byKey(const Key('fixed-region')));
    final layout = tester.getSize(find.byKey(const Key('play-layout')));
    final formerMapHeight = layout.height * 0.6 + 12;
    final formerTipHeight = (layout.height - formerMapHeight - 16) * .4;
    expect(fixed.height, closeTo(formerMapHeight + formerTipHeight + 8, 1));
    expect(
      tester.getSize(find.byType(TerritoryMap)).height,
      closeTo(fixed.height, 1),
    );
    expect(tester.widget<Text>(find.byKey(const Key('tip-text'))).maxLines, 4);
    expectMapControlsInside(tester);
    final tipsRect = tester.getRect(find.byKey(const Key('tips-region')));
    expect(tipsRect.right, closeTo(fixed.right - 8, .01));
    expect(
      tester.widget<IconButton>(find.byKey(const Key('map-home'))).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('地名から本拠地を探す'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '油留木町'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '奈良市'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '油留木町');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '油留木町'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '油留木町'));
    await tester.pumpAndSettle();
    expect(find.text('奈良県 奈良市 油留木町'), findsOneWidget);
    await tester.ensureVisible(find.text('ここを本拠地にする'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ここを本拠地にする'));
    await tester.pumpAndSettle();
    expect(find.text('この地域はあなたの領土です'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tips-region')), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('tip-details-button')), findsNothing);
    final homeTown =
        tester
            .widget<TerritoryMap>(find.byType(TerritoryMap))
            .atlas
            .towns['292010010']!;
    expect(
      tester.widget<Text>(find.byKey(const Key('attack-progress'))).data,
      '${number(homeTown.population)} / ${number(homeTown.population)}',
    );
    final initialScale =
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis();
    await tester.tap(find.byKey(const Key('map-home')));
    await tester.pumpAndSettle();
    expectCenteredOn(tester, '292010010');
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      initialScale,
    );
    final map = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
    final target = map.atlas.towns.values.firstWhere(
      (t) => map.game.canAttack(t.id) && t.population > 10,
    );
    map.onSelected(target.id);
    await tester.pumpAndSettle();
    final firstTip =
        tester.widget<Text>(find.byKey(const Key('tip-text'))).data;
    await tester.pump(const Duration(seconds: 4));
    expect(
      tester.widget<Text>(find.byKey(const Key('tip-text'))).data,
      firstTip,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final timedTip =
        tester.widget<Text>(find.byKey(const Key('tip-text'))).data;
    expect(timedTip, isNot(firstTip));
    final attackRect = tester.getRect(find.byKey(const Key('attack')));
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('attack')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('tip-text'))).data,
      timedTip,
    );
    expect(map.game.progress[target.id], 10);
    final other = map.atlas.towns.values.firstWhere(
      (t) => t.id != target.id && map.game.isReachable(t.id),
    );
    map.onSelected(other.id);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TerritoryMap>(find.byType(TerritoryMap)).selected,
      target.id,
    );
    expect(map.game.attackTarget, target.id);
    expect(map.game.progress.containsKey(other.id), isFalse);
    ScaffoldMessenger.of(
      tester.element(find.byType(TerritoryMap)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('attack-progress'))).data,
      startsWith('10 / '),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('city-progress'))).data,
      startsWith(
        '${map.atlas.cities[target.cityId]} ${number(map.game.currentCityPopulation(target.cityId))} / ',
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('prefecture-progress'))).data,
      '奈良県 ${number(map.atlas.towns[map.game.home]!.population + 10)} / 1,324,473',
    );
    expect(
      tester.getRect(find.byKey(const Key('attack-progress'))).bottom,
      lessThan(fixed.top),
    );
    expect(tester.getRect(find.byKey(const Key('fixed-region'))), fixed);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戦績'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('attack'))), attackRect);
    await tester.tap(find.byTooltip('戦績を閉じる'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('fixed-region'))), fixed);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ヘルプ'));
    await tester.pumpAndSettle();
    expect(find.text('大和国の歩き方'), findsOneWidget);
    Navigator.of(tester.element(find.text('大和国の歩き方'))).pop();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('fixed-region'))), fixed);
    await tester.ensureVisible(find.byTooltip('県全域を表示'));
    await tester.tap(find.byTooltip('県全域を表示'));
    await tester.pumpAndSettle();
    expect(find.text('奈良県'), findsOneWidget);
    expect(find.text('ここを本拠地にする'), findsNothing);
    await tester.tap(find.byKey(const Key('map-home')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TerritoryMap>(find.byType(TerritoryMap)).selected,
      target.id,
    );
    expectCenteredOn(tester, target.id);
    await tester.tap(find.byTooltip('拡大'));
    await tester.pumpAndSettle();
    final zoomedScale =
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis();
    await tester.drag(find.byType(InteractiveViewer), const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map-home')));
    await tester.pumpAndSettle();
    expectCenteredOn(tester, target.id);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      zoomedScale,
    );
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expectMapControlsInside(tester);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('kunitori.nara.v1'), contains('292010010'));
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戦績'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('大和への第一歩'), 150);
    expect(find.text('大和への第一歩'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('最初からやり直す'), 150);
    await tester.ensureVisible(find.text('最初からやり直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最初からやり直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(prefs.getString('kunitori.nara.v1'), contains('292010010'));
    await tester.tap(find.text('最初からやり直す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('やり直す'));
    await tester.pumpAndSettle();
    expect(find.text('奈良県'), findsOneWidget);
    expect(find.text('旅のはじまり'), findsOneWidget);
    final saved =
        jsonDecode(prefs.getString('kunitori.nara.v1')!)
            as Map<String, dynamic>;
    expect(saved['home'], isNull);
    expect(saved['owned'], isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const KunitoriApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(find.text('奈良県'), findsOneWidget);
    expect(find.text('旅のはじまり'), findsOneWidget);
    final actionRect = tester.getRect(find.byKey(const Key('action-region')));
    for (final size in TipSize.values) {
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャラ・吹き出し'));
      await tester.pumpAndSettle();
      final field = find.byType(DropdownButtonFormField<TipSize>);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(size.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('tips設定を閉じる'));
      await tester.pumpAndSettle();
      final mapRect = tester.getRect(find.byKey(const Key('fixed-region')));
      final tipRect = tester.getRect(find.byKey(const Key('tips-region')));
      expect(mapRect.contains(tipRect.center), isTrue);
      expect(tipRect.bottom, lessThanOrEqualTo(mapRect.bottom));
      expect(
        tester.getRect(find.byKey(const Key('action-region'))),
        actionRect,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャラ・吹き出し'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tipsを表示'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('tips設定を閉じる'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tips-region')), findsNothing);
    expect(tester.getRect(find.byKey(const Key('action-region'))), actionRect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const KunitoriApp());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tips-region')), findsNothing);
    expect(tester.getRect(find.byKey(const Key('action-region'))), actionRect);
    expect(jsonDecode(prefs.getString('kunitori.nara.v1')!)['owned'], isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

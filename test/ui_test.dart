import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/main.dart';

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
    expect(find.text('くにとり'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('市町村・町丁字を探す'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '油留木町'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '奈良市'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '油留木町');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '油留木町'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '油留木町'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ここを本拠地にする'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ここを本拠地にする'));
    await tester.pumpAndSettle();
    expect(find.text('この地域はあなたの領土です'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('県全域を表示'));
    await tester.tap(find.byTooltip('県全域を表示'));
    await tester.pumpAndSettle();
    expect(find.text('奈良県 · 市区町村'), findsOneWidget);
    expect(find.text('ここを本拠地にする'), findsNothing);
    await tester.tap(find.byTooltip('本拠地へ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('kunitori.nara.v1'), contains('292010010'));
    await tester.tap(find.text('戦績'));
    await tester.pumpAndSettle();
    expect(find.text('大和への第一歩'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

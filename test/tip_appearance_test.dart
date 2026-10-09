import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/tip_appearance.dart';
import 'package:kunitori/tip_presenter.dart';
import 'package:kunitori/tip_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'appearance persists independently of game data, latest change wins',
    () async {
      SharedPreferences.setMockInitialValues({
        'kunitori.nara.v1': 'existing game',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = TipAppearanceStore(prefs);
      final appearance = const TipAppearance().copyWith(
        showCharacter: false,
        showBubble: false,
        character: TipCharacter.deer,
        bubbleStyle: TipBubbleStyle.mint,
        bubbleShape: TipBubbleShape.square,
        characterOnRight: true,
        size: TipSize.large,
      );
      await Future.wait([
        store.save(const TipAppearance(showTips: false)),
        store.save(appearance),
      ]);
      expect(TipAppearanceStore(prefs).load().toJson(), appearance.toJson());
      expect(prefs.getString('kunitori.nara.v1'), 'existing game');
      await prefs.setString(TipAppearanceStore.key, '{bad');
      expect(store.load().toJson(), const TipAppearance().toJson());
      expect(
        TipAppearance.fromJson({
          'character': 'future',
          'showTips': 123,
        }).toJson(),
        const TipAppearance().toJson(),
      );
    },
  );

  test(
    'legacy controls tips reclaim space without changing the action height',
    () {
      final appearance = TipAppearance.fromJson({
        'placement': 'controls',
        'size': 'large',
        'showTips': true,
      });
      expect(appearance.placement, TipPlacement.mapBottom);
      expect(appearance.controlInsetSize, TipSize.large);
      final changed = appearance.copyWith(size: TipSize.small, showTips: false);
      expect(
        TipAppearance.fromJson(changed.toJson()).controlInsetSize,
        TipSize.large,
      );
      expect(
        TipAppearance.fromJson({
          'placement': 'controls',
          'showTips': false,
        }).controlInsetSize,
        isNull,
      );
      expect(
        TipAppearance.fromJson({'placement': 'mapTop'}).placement,
        TipPlacement.mapBottom,
      );
    },
  );

  testWidgets(
    'designs fit narrow map overlay, including long tips and both character positions',
    (tester) async {
      final font = FontLoader('NotoSansJP')
        ..addFont(rootBundle.load('assets/fonts/NotoSansJP.ttf'));
      await font.load();
      final atlas = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final tips =
          Game(atlas).tipsFor(selectedCity: '29201').map((f) => f.text).toList()
            ..sort((a, b) => b.length.compareTo(a.length));
      for (final size in TipSize.values) {
        for (final shape in TipBubbleShape.values) {
          for (final style in TipBubbleStyle.values) {
            for (final right in [false, true]) {
              final a = TipAppearance(
                size: size,
                bubbleShape: shape,
                bubbleStyle: style,
                characterOnRight: right,
                character: right ? TipCharacter.deer : TipCharacter.guide,
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData(fontFamily: 'NotoSansJP'),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 240,
                        child: TipPresenter(text: tips.first, appearance: a),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(
                find.byKey(const Key('tip-text')),
              );
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '${size.name}/${shape.name}/${style.name}/$right',
              );
              expect(
                tester.getSize(find.byKey(const Key('tips-region'))).height,
                size.height,
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
      for (final a in [
        const TipAppearance(showCharacter: false),
        const TipAppearance(showBubble: false),
        const TipAppearance(showTips: false),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TipPresenter(text: '奈良のtips', appearance: a)),
          ),
        );
        expect(
          find.byKey(const Key('tip-character')),
          a.showTips && a.showCharacter ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('tip-text')),
          a.showTips ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'settings update preview and allow independent visibility toggles',
    (tester) async {
      var appearance = const TipAppearance();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TipSettings(
              initial: appearance,
              onChanged: (a) => appearance = a,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャラを表示'));
      await tester.pumpAndSettle();
      expect(appearance.showCharacter, isFalse);
      expect(find.byKey(const Key('tip-character')), findsNothing);
      await tester.tap(find.text('吹き出しを表示'));
      await tester.pumpAndSettle();
      expect(appearance.showBubble, isFalse);
      expect(find.byKey(const Key('tip-text')), findsOneWidget);
      await tester.tap(find.text('tipsを表示'));
      await tester.pumpAndSettle();
      expect(appearance.showTips, isFalse);
      expect(find.text('tipsは非表示です'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

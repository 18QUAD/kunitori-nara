import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/regional_ads.dart';
import 'package:kunitori/regional_ad_card.dart';
import 'package:kunitori/save_store.dart';
import 'package:kunitori/tip_presenter.dart';
import 'package:kunitori/tip_appearance.dart';

Map<String, dynamic> adJson(String city) => {
  'cityId': city,
  'category': 'product',
  'name': 'テスト用の地元商品',
  'advertiser': 'テスト用の地元企業',
  'url': 'https://hb.afl.rakuten.co.jp/hgc/test/',
};

void main() {
  test('unsafe links and other municipality ads are rejected', () {
    expect(RegionalAd.parse(adJson('29201'), '29201'), isNotNull);
    expect(RegionalAd.parse(adJson('29206'), '29201'), isNull);
    expect(
      RegionalAd.parse({
        ...adJson('29201'),
        'url': 'https://hb.afl.rakuten.co.jp.evil.test/',
      }, '29201'),
      isNull,
    );
    expect(
      RegionalAd.parse({
        ...adJson('29201'),
        'url': 'javascript:alert(1)',
      }, '29201'),
      isNull,
    );
  });

  test(
    'requests coalesce, valid results cache, and invalid/failed results hide ads',
    () async {
      var calls = 0;
      final repository = RegionalAdRepository(
        Uri.parse('https://worker.test/ads'),
        client: MockClient((request) async {
          calls++;
          final city = request.url.queryParameters['city']!;
          if (city == '29202') return http.Response('unavailable', 503);
          return http.Response(
            jsonEncode({
              'cityId': city,
              'expiresAt':
                  DateTime.now()
                      .add(const Duration(minutes: 10))
                      .toIso8601String(),
              'ads': [adJson(city), adJson('13101')],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(repository.dispose);
      final results = await Future.wait([
        repository.load('29201'),
        repository.load('29201'),
      ]);
      expect(results.first.ads.length, 1);
      expect(calls, 1);
      await repository.load('29201');
      expect(calls, 1);
      expect((await repository.load('29202')).ads, isEmpty);
      expect((await repository.load('13101')).ads, isEmpty);
    },
  );

  test('expired API data is not displayed', () async {
    final repository = RegionalAdRepository(
      Uri.parse('https://worker.test/ads'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'cityId': '29201',
            'expiresAt': '2020-01-01T00:00:00Z',
            'ads': [adJson('29201')],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(repository.dispose);
    expect((await repository.load('29201')).ads, isEmpty);
  });

  testWidgets('card fits a narrow tips area and opens only on tap', (
    tester,
  ) async {
    var opens = 0;
    for (final height in [48.0, 100.0, 116.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: height,
                child: RegionalAdCard(
                  ad: RegionalAd.parse(adJson('29201'), '29201')!,
                  cityName: '奈良市',
                  maxHeight: height,
                  onOpen: () => opens++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('PR · 奈良市 · 地元企業'), findsOneWidget);
      expect(find.text('楽天市場で詳細を見る ↗'), findsOneWidget);
      await tester.tap(find.byKey(const Key('regional-ad-card')));
    }
    expect(opens, 3);
  });

  testWidgets('campaign city wins over map selection; ads rotate inside tips', (
    tester,
  ) async {
    final source = await tester.runAsync(
      () => rootBundle.loadString('assets/data/nara.json'),
    );
    final atlas = Atlas.fromJson(jsonDecode(source!) as Map<String, dynamic>);
    final game = Game(atlas);
    final home = atlas.byCity['29201']!.first;
    game.setHome(home.id);
    final target = home.neighbors.firstWhere(
      (id) => !game.owned.contains(id) && atlas.towns[id]!.population > 1,
    );
    game.tap(target, DateTime.now());
    final city = atlas.towns[target]!.cityId;
    expect(advertisingCity(game, selectedCity: '29206'), city);
    SharedPreferences.setMockInitialValues({
      SaveStore.key: jsonEncode(game.toJson()),
    });
    final requested = <String>[];
    final repository = RegionalAdRepository(
      Uri.parse('https://worker.test/ads'),
      client: MockClient((request) async {
        final id = request.url.queryParameters['city']!;
        requested.add(id);
        return http.Response(
          jsonEncode({
            'cityId': id,
            'expiresAt':
                DateTime.now()
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
            'ads': [adJson(id)],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KunitoriApp(adRepository: repository));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (requested.isNotEmpty) break;
    }
    await tester.pump();
    expect(requested, [city]);
    expect(find.byKey(const Key('regional-ad-card')), findsNothing);
    final tipRect = tester.getRect(find.byKey(const Key('tips-region')));
    final characterRect = tester.getRect(
      find.byKey(const Key('tip-character')),
    );
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.byKey(const Key('regional-ad-card')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('tips-region'))), tipRect);
    expect(
      tester.getRect(find.byKey(const Key('tip-character'))),
      characterRect,
    );
    final bubble = tester.getRect(find.byKey(const Key('tip-bubble')));
    final card = tester.getRect(find.byKey(const Key('regional-ad-card')));
    expect(bubble.contains(card.topLeft), isTrue);
    expect(bubble.contains(card.bottomRight), isTrue);
    final map = tester.getRect(find.byKey(const Key('fixed-region')));
    expect(
      map.contains(
        tester.getRect(find.byKey(const Key('regional-ad-card'))).center,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('regional-ad-card')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'long advertisements stay within the same tips bubble across sizes',
    (tester) async {
      final ad =
          RegionalAd.parse({
            ...adJson('29201'),
            'name': '奈良の地元企業の商品名が長い場合も吹き出しの内側に収まるように表示するテスト用の商品です',
          }, '29201')!;
      for (final width in [280.0, 320.0, 390.0]) {
        for (final size in TipSize.values) {
          for (final scale in [1.0, 2.0]) {
            for (final right in [false, true]) {
              final appearance = TipAppearance(
                size: size,
                characterOnRight: right,
              );
              Widget frame(Widget? content) => MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: SizedBox(
                        width: width,
                        height: size.height,
                        child: TipPresenter(
                          text: '通常のtips',
                          appearance: appearance,
                          content: content,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpWidget(frame(null));
              final original = tester.getRect(
                find.byKey(const Key('tips-region')),
              );
              await tester.pumpWidget(
                frame(
                  RegionalAdCard(
                    ad: ad,
                    cityName: '奈良市',
                    maxHeight: size.height,
                    embedded: true,
                    onOpen: () {},
                  ),
                ),
              );
              expect(
                tester.getRect(find.byKey(const Key('tips-region'))),
                original,
              );
              final bubble = tester.getRect(
                find.byKey(const Key('tip-bubble')),
              );
              final card = tester.getRect(
                find.byKey(const Key('regional-ad-card')),
              );
              expect(bubble.contains(card.topLeft), isTrue);
              expect(bubble.contains(card.bottomRight), isTrue);
              expect(
                tester.takeException(),
                isNull,
                reason: 'width=$width, size=$size, scale=$scale, right=$right',
              );
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}

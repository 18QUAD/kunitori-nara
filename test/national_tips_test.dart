import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_tips.dart';

class TipsBundle extends CachingAssetBundle {
  final files = <String, String>{};
  final requests = <String>[];
  final holds = <String, Completer<String>>{};
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    expect(cache, isFalse);
    requests.add(key);
    return holds[key]?.future ?? files[key]!;
  }
}

void main() {
  late Atlas atlas;
  late TipsBundle bundle;
  late NationalTips tips;
  const id24 = '24208:national:000000000024';
  const id26 = '26201:national:000000000026';
  setUp(() async {
    final data = jsonDecode(File('assets/data/nara.json').readAsStringSync());
    atlas = Atlas.fromJson({
      'cities': [
        ...data['cities'],
        {'id': '24208', 'name': '名張市'},
        {'id': '26201', 'name': '福知山市'},
      ],
      'towns': [
        ...data['towns'],
        for (final city in ['24208', '26201'])
          {
            'id': '${city}0010',
            'name': '中央町',
            'cityId': city,
            'population': 100,
            'area': 1,
            'neighbors': [],
            'polygons': [],
          },
      ],
    });
    bundle = TipsBundle();
    bundle.files['assets/data/tips/index.json'] = jsonEncode({
      'tips': 2,
      'knownIds': [id24, id26],
    });
    for (final city in ['24208', '26201']) {
      bundle
          .files['assets/data/tips/${city.substring(0, 2)}.json'] = jsonEncode({
        'prefectureId': city.substring(0, 2),
        'cities': {
          city: [
            {
              'id': city == '24208' ? id24 : id26,
              'cityId': city,
              'category': '地理',
              'text': '地域の中央には川が流れています。',
              'source': 'https://ja.wikipedia.org/w/index.php?title=地域&oldid=1',
            },
          ],
        },
      });
    }
    tips = await NationalTips.load(atlas, bundle: bundle);
  });

  test(
    'loads only requested text, releases previous prefecture and keeps Nara',
    () async {
      final nara = atlas.facts['29205'];
      final fallback24 = atlas.facts['24208'];
      expect(bundle.requests, ['assets/data/tips/index.json']);
      await tips.ensure('24');
      expect(atlas.facts['24208']!.single.id, id24);
      expect(atlas.facts['24208']!.single.quizEligible, isFalse);
      await tips.ensure('24');
      expect(bundle.requests.where((p) => p.endsWith('24.json')), hasLength(1));
      await tips.ensure('26');
      expect(identical(atlas.facts['24208'], fallback24), isTrue);
      expect(atlas.facts['26201']!.single.id, id26);
      await tips.ensure('29');
      expect(tips.residentPrefecture, isNull);
      expect(atlas.facts['26201']!.first.category, '仮tips');
      expect(identical(atlas.facts['29205'], nara), isTrue);
      expect(bundle.requests.any((p) => p.endsWith('29.json')), isFalse);
    },
  );

  test('latest request wins when an older prefecture finishes later', () async {
    const path = 'assets/data/tips/24.json';
    bundle.holds[path] = Completer<String>();
    final old = tips.ensure('24');
    await tips.ensure('26');
    bundle.holds[path]!.complete(bundle.files[path]);
    expect(await old, isFalse);
    expect(tips.residentPrefecture, '26');
    expect(atlas.facts['24208']!.first.category, '仮tips');
    expect(atlas.facts['26201']!.single.id, id26);
  });

  test(
    'saved reading history and campaign survive releasing text and restarting',
    () async {
      final game =
          Game(atlas)
            ..setHome('29205043001')
            ..selectAttackTarget('29205041001');
      game.tap('29205041001', DateTime.utc(2026));
      game.observe('24208'); // Old placeholder IDs remain valid too.
      await tips.ensure('24');
      game.seen.add(id24);
      final save = game.toJson();
      await tips.ensure(null);
      await NationalTips.load(atlas, bundle: bundle);
      expect(Game.restore(atlas, save).toJson(), save);
      game.seen.add('24208:national:ffffffffffff');
      expect(() => Game.restore(atlas, game.toJson()), throwsFormatException);
    },
  );

  test('a running Nara quiz retains questions and absolute deadline', () async {
    const city = '29362';
    final game = Game(atlas)..setHome(atlas.officeTownIds[city]!);
    game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    game.everOwned.addAll(game.owned);
    game.startQuizAt(game.home!, DateTime.utc(2026));
    final save = game.toJson();
    await tips.ensure('24');
    await tips.ensure(null);
    final restored = Game.restore(atlas, save);
    expect(restored.toJson(), save);
    expect(restored.quiz!.deadline, game.quiz!.deadline);
  });
}

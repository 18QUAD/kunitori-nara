import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';

void main() {
  late Atlas atlas;
  final now = DateTime.utc(2026, 10, 8);
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
  });
  Game ready(String city) {
    final game = Game(atlas)..startAt(atlas.byCity[city]!.first.id);
    game.owned.addAll(atlas.byCity[city]!.map((t) => t.id));
    game.everOwned.addAll(game.owned);
    return game;
  }

  test('generated office constants match the bundled source records', () {
    final data = jsonDecode(
      File('assets/data/nara_offices.json').readAsStringSync(),
    );
    expect(data['offices'], hasLength(39));
    for (final record in data['offices']) {
      final office = atlas.offices[record['cityId']]!;
      expect(office.name, record['name']);
      expect(office.address, record['address']);
      expect(office.sourceTownId, record['sourceTownId']);
      expect([office.longitude, office.latitude], record['point']);
      expect(office.officialUrl, record['officialUrl']);
      expect(
        record['coordinateSourceSha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    }
  });

  test('pre-upgrade saves retain mastered cities and possessions', () {
    final old = ready('29205');
    old.mastered.add('29205');
    old.wins = 2;
    old.totalTaps = 10;
    final data = old.toJson()..remove('quizRule');
    final loaded = Game.restore(atlas, data);
    expect(loaded.lastCapturedTownId, old.lastCapturedTownId);
    expect(loaded.owned, old.owned);
    expect(loaded.everOwned, old.everOwned);
    expect(loaded.mastered, old.mastered);
    expect(loaded.totalTaps, 10);
    expect(loaded.wins, 2);
  });

  test('all 39 offices remain mapped but no conquest quiz can start', () {
    expect(atlas.officeTownIds, hasLength(39));
    for (final city in atlas.cities.keys) {
      final game = ready(city);
      final office = atlas.officeTownIds[city]!;
      expect(atlas.towns[office]!.cityId, city);
      expect(game.canStartQuizAt(office), isFalse);
      game.startQuizAt(office, now);
      expect(game.quiz, isNull);
      expect(Game.restore(atlas, game.toJson()).mastered, contains(city));
    }
  });
}

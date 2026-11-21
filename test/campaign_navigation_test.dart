import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/national_atlas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Atlas atlas;
  final now = DateTime.utc(2026, 11, 21);
  const initial = '29205043001';
  const next = '29205041001';
  setUpAll(() async => atlas = (await NationalAtlas.load()).atlas);

  Game capturedNext() {
    final game = Game(atlas)..startAt(initial);
    game.progress[next] = game.requiredTaps(atlas.towns[next]!) - 1;
    expect(game.tap(next, now), isTrue);
    return game;
  }

  test('an empty campaign has no navigation destination', () {
    final game = Game(atlas);
    expect(game.hasStarted, isFalse);
    expect(game.campaignFocusTownId, isNull);
    expect(game.toJson().containsKey('home'), isFalse);
  });

  test(
    'current attack takes priority; completing it focuses the latest capture',
    () {
      final game = Game(atlas)..startAt(initial);
      expect(game.campaignFocusTownId, initial);
      game.selectAttackTarget(next);
      expect(game.tap(next, now), isFalse);
      expect(game.campaignFocusTownId, next);
      expect(game.lastCapturedTownId, initial);
      game.progress[next] = game.requiredTaps(atlas.towns[next]!) - 1;
      expect(game.tap(next, now), isTrue);
      expect(game.attackTarget, isNull);
      expect(game.lastCapturedTownId, next);
      expect(game.campaignFocusTownId, next);
      expect(game.campaignFocusTownId, isNot(initial));
      final before = {...game.owned};
      game.startAt(atlas.towns.keys.last);
      expect(game.owned, before);
    },
  );

  test(
    'latest capture and ongoing attack survive saving independently of list order',
    () {
      final game = capturedNext();
      final save =
          jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>;
      save['owned'] = (save['owned'] as List).reversed.toList();
      final restored = Game.restore(atlas, save);
      expect(restored.campaignFocusTownId, next);
      expect(restored.lastCapturedTownId, next);
      expect(restored.owned, game.owned);
      final target = atlas.towns[next]!.neighbors.firstWhere(
        (id) => !game.owned.contains(id),
      );
      game.selectAttackTarget(target);
      game.tap(target, now);
      final active = Game.restore(atlas, jsonDecode(jsonEncode(game.toJson())));
      expect(active.campaignFocusTownId, target);
      expect(active.lastCapturedTownId, next);
      expect(active.progress, game.progress);
    },
  );

  test('old home saves use acquisition order instead of the former base', () {
    final game = capturedNext();
    final save =
        game.toJson()
          ..remove('navigationRule')
          ..remove('lastCapturedTownId')
          ..['home'] = initial;
    final restored = Game.restore(atlas, save);
    expect(restored.campaignFocusTownId, next);
    expect(restored.owned, game.owned);
    expect(restored.everOwned, game.everOwned);
    expect(restored.totalTaps, game.totalTaps);
    expect(restored.toJson().containsKey('home'), isFalse);
    expect(Game.restore(atlas, restored.toJson()).toJson(), restored.toJson());
  });

  test(
    'invalid latest-capture IDs and unknown navigation formats are rejected',
    () {
      final game = capturedNext();
      expect(
        () => Game.restore(atlas, {
          ...game.toJson(),
          'lastCapturedTownId': 'unknown',
        }),
        throwsFormatException,
      );
      expect(
        () =>
            Game.restore(atlas, {...game.toJson(), 'navigationRule': 'future'}),
        throwsFormatException,
      );
    },
  );
}

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'game.dart';

/// Immutable display state: Game itself mutates between widget rebuilds.
class MapPaintSnapshot {
  MapPaintSnapshot(this.game)
    : home = game.home,
      target = game.attackTarget,
      owned = game.owned.length,
      mastered = game.mastered.length,
      quiz = game.quiz,
      bands = {
        for (final entry in game.progress.entries)
          if (entry.value *
                  10 ~/
                  math.max(1, game.atlas.towns[entry.key]!.population) >
              0)
            entry.key: (entry.value *
                    10 ~/
                    math.max(1, game.atlas.towns[entry.key]!.population))
                .clamp(0, 10),
      };
  final Game game;
  final String? home, target;
  final int owned, mastered;
  final Object? quiz;
  final Map<String, int> bands;

  bool sameColors(MapPaintSnapshot other) =>
      identical(game, other.game) &&
      home == other.home &&
      owned == other.owned &&
      mapEquals(bands, other.bands);

  bool sameForeground(MapPaintSnapshot other) =>
      identical(game, other.game) &&
      home == other.home &&
      target == other.target &&
      owned == other.owned &&
      mastered == other.mastered &&
      identical(quiz, other.quiz);
}

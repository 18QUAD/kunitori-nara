import 'dart:convert';
import 'dart:io';
import 'package:kunitori/game.dart';

// Run from the repository root: dart test/web/conquest_fixture.dart OUTPUT.json
void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Output JSON path is required');
  final atlas = Atlas.fromJson(
    jsonDecode(
      File.fromUri(
        Platform.script.resolve('../../assets/data/nara.json'),
      ).readAsStringSync(),
    ),
  );
  final g = Game(atlas)..setHome('29205043001');
  const target = '29205041001';
  final town = atlas.towns[target]!;
  g.owned.addAll(
    atlas.byCity[town.cityId]!.where((t) => t.id != target).map((t) => t.id),
  );
  g.everOwned.addAll(g.owned);
  g.attackTarget = target;
  g.progress[target] = g.requiredTaps(town) - 2;
  g.totalTaps =
      g.owned
          .where((id) => id != g.home)
          .fold(0, (n, id) => n + g.requiredTaps(atlas.towns[id]!)) +
      g.progress[target]!;
  g.cityTaps[town.cityId] = g.totalTaps;
  File(args.single).writeAsStringSync(
    jsonEncode({'game': g.toJson(), 'population': town.population}),
  );
}

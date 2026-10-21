// Export the game's merged town IDs and physical adjacency for offline tools.
import 'dart:convert';
import 'dart:io';
import 'package:kunitori/game.dart';
import 'package:kunitori/town_connections.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: dart tools/export_town_graph.dart ASSET_DIR OUTPUT',
    );
  }
  Map<String, dynamic> read(String name) =>
      jsonDecode(File('${args[0]}/$name').readAsStringSync())
          as Map<String, dynamic>;
  final nara = read('nara_metadata.json');
  final national = read('japan.json');
  final atlas = Atlas.fromJson({
    'cities': [...nara['cities'] as List, ...national['cities'] as List],
    'towns': [...nara['towns'] as List, ...national['towns'] as List],
  });
  for (final pair in [
    ...national['crossPrefectureNeighbors'] as List,
    ...national['crossMunicipalityNeighbors'] as List? ?? [],
  ]) {
    final a = atlas.sourceToTown[pair[0]]!;
    final b = atlas.sourceToTown[pair[1]]!;
    if (a != b) {
      atlas.towns[a]!.neighbors.add(b);
      atlas.towns[b]!.neighbors.add(a);
    }
  }
  File(args[1]).writeAsStringSync(
    jsonEncode({
      'cities': atlas.cities,
      'sourceToTown': atlas.sourceToTown,
      'seaConnections': seaTownConnections,
      'towns': [
        for (final t in atlas.towns.values)
          {
            'id': t.id,
            'cityId': t.cityId,
            'name': t.name,
            'population': t.population,
            'neighbors': t.neighbors.toList(),
          },
      ],
    }),
  );
  stdout.writeln('Exported ${atlas.towns.length} merged game towns.');
}

// Export the exact gameplay grouping for the offline border-image builder.
import 'dart:convert';
import 'dart:io';
import 'package:kunitori/game.dart';

void main() {
  Map<String, dynamic> read(String name) =>
      jsonDecode(File('assets/data/$name.json').readAsStringSync());
  final nara = read('nara_metadata');
  final japan = read('japan');
  final atlas = Atlas.fromJson({
    'cities': [...nara['cities'], ...japan['cities']],
    'towns': [...nara['towns'], ...japan['towns']],
  });
  final output = File('data/raw/border_tiles/groups.json');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    jsonEncode({
      'sourceToTown': atlas.sourceToTown,
      'townCount': atlas.towns.length,
    }),
  );
  stdout.writeln('Exported ${atlas.towns.length} gameplay town groups');
}

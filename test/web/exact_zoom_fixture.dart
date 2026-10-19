import 'dart:convert';
import 'dart:io';
import 'package:kunitori/game.dart';

// Canonical IDs come from the game importer, including nationwide chome merges.
void main(List<String> args) {
  final japan = jsonDecode(File('assets/data/japan.json').readAsStringSync());
  final nara = jsonDecode(
    File('assets/data/nara_metadata.json').readAsStringSync(),
  );
  final atlas = Atlas.fromJson({
    'cities': [...nara['cities'], ...japan['cities']],
    'towns': [...nara['towns'], ...japan['towns']],
  });
  File(args.single).writeAsStringSync(
    jsonEncode(atlas.towns.keys.where((id) => id.startsWith('24')).toList()),
  );
}

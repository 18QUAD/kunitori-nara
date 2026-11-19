/// Presentation names selected from the 2020 census upper/lower name fields.
/// Never use these names for merging, graph construction, answers or save keys.
/// Rules and reproduction: docs/town-name-audit/naming-rules/README.txt.
library;

part 'generated/town_display_names.g.dart';

String townDisplayName(String id, String name) {
  final reviewed = townDisplayNames[id];
  return reviewed?.sourceName == name ? reviewed!.displayName : name;
}

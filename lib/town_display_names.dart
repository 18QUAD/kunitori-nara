/// Reviewed presentation names, keyed by census region ID. Never use these
/// names for merging towns, graph construction, quiz answers, or save keys.
/// Evidence and unresolved candidates: docs/town-name-audit/README.txt.
const townDisplayNames = <String, ({String sourceName, String displayName})>{
  '26211010001': (sourceName: '田辺田辺', displayName: '田辺'),
};

String townDisplayName(String id, String name) {
  final reviewed = townDisplayNames[id];
  return reviewed?.sourceName == name ? reviewed!.displayName : name;
}

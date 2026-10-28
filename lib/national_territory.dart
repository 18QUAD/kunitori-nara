import 'dart:math';
import 'dart:ui';
import 'prepared_territory.dart';

/// Read only requested offline-unioned town contours. No census JSON, parent
/// outline construction or source-town merging is performed at display time.
Future<Map<String, Path>> loadNationalTerritory({
  required String prefecture,
  required Set<String> towns,
  required Map<String, String> sourceToTown,
  required Offset Function(Point<double>) project,
  required bool Function() isCurrent,
}) async {
  final paths = <String, Path>{};
  try {
    final prepared = await PreparedTerritory.load(prefecture);
    if (!isCurrent()) return paths;
    for (final id in towns) {
      if (sourceToTown[id] != id) throw FormatException('Invalid town ID $id');
      paths[id] = prepared.path(id, project);
    }

    return paths;
  } catch (error) {
    for (final path in paths.values) {
      path.reset();
    }

    rethrow;
  }
}

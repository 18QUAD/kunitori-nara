import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Map<String, (String, int, int)>? _locations;

/// Tests read the same prepared bytes as the worker, without copying every
/// image into Flutter's asset manifest or requiring an untracked render cache.
Uint8List preparedMapBytes(String name) {
  final loose = File(name);
  if (loose.existsSync()) return loose.readAsBytesSync();
  if (_locations == null) {
    final manifest = jsonDecode(
      File('data/prepared_maps/map-image-manifest.json').readAsStringSync(),
    );
    final locations = <String, (String, int, int)>{};
    for (final pack in manifest['packs']) {
      var offset = 0;
      for (var i = pack[3] as int; i < pack[4]; i++) {
        final entry = manifest['assets'][i];
        final length = entry[1] as int;
        locations['assets/data/map_images/${entry[0]}'] = (
          'data/prepared_maps/${pack[0]}',
          offset,
          length,
        );
        offset += length;
      }
    }
    _locations = locations;
  }
  final (path, offset, length) = _locations![name]!;
  final file = File(path).openSync();
  try {
    file.setPositionSync(offset);
    return file.readSync(length);
  } finally {
    file.closeSync();
  }
}

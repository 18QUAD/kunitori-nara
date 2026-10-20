import 'dart:convert';
import 'dart:typed_data';

// Small independent KNT4 fixture for storage failure/serialization tests.
ByteData preparedFixture(Map<String, List<dynamic>> shapes) {
  final body = BytesBuilder();
  final entries = <({String id, int start, int length})>[];
  void uint(int n) {
    body.add(
      (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List(),
    );
  }

  for (final entry in shapes.entries) {
    final start = body.length;
    uint(entry.value.length);
    for (final polygon in entry.value) {
      uint((polygon as List).length);
      for (final ring in polygon) {
        body.addByte(0);
        uint((ring as List).length);
        for (final point in ring) {
          final pair =
              ByteData(16)
                ..setFloat64(0, (point[0] as num).toDouble(), Endian.little)
                ..setFloat64(8, (point[1] as num).toDouble(), Endian.little);
          body.add(pair.buffer.asUint8List());
        }
      }
    }
    entries.add((id: entry.key, start: start, length: body.length - start));
  }
  final header = 8 + entries.fold<int>(0, (n, e) => n + 9 + e.id.length);
  final result =
      BytesBuilder()
        ..add(ascii.encode('KNT4'))
        ..add(
          (ByteData(4)
            ..setUint32(0, entries.length, Endian.little)).buffer.asUint8List(),
        );
  for (final entry in entries) {
    final offset =
        ByteData(8)
          ..setUint32(0, header + entry.start, Endian.little)
          ..setUint32(4, entry.length, Endian.little);
    result
      ..addByte(entry.id.length)
      ..add(ascii.encode(entry.id))
      ..add(offset.buffer.asUint8List());
  }
  result.add(body.takeBytes());
  return ByteData.sublistView(result.takeBytes());
}

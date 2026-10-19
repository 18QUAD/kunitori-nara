import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'map_image_budget.dart';

/// Web uses the verified disk packs in its worker. Native builds read the same
/// prepared packs from the app bundle; neither platform generates map pixels.
class PreparedMapBytes {
  PreparedMapBytes() {
    MapImageBudget.shared.addListener(_trim);
  }
  static final shared = PreparedMapBytes();
  Future<void>? _index;
  final _locations = <String, int>{};
  late Uint32List _sizes, _packs, _offsets;
  late List<String> _paths;
  final _memory = <int, Uint8List>{};
  final _pending = <int, Future<Uint8List>>{};
  int _bytes = 0;

  Future<void> _loadIndex() async {
    final data = jsonDecode(
      await rootBundle.loadString(
        'data/prepared_maps/map-image-manifest.json',
        cache: false,
      ),
    );
    final assets = data['assets'] as List;
    _sizes = Uint32List(assets.length);
    _packs = Uint32List(assets.length);
    _offsets = Uint32List(assets.length);
    _paths = [
      for (final pack in data['packs']) 'data/prepared_maps/${pack[0]}',
    ];
    for (var p = 0; p < _paths.length; p++) {
      final pack = data['packs'][p];
      var offset = 0;
      for (var i = pack[3] as int; i < pack[4]; i++) {
        _locations[assets[i][0] as String] = i;
        _sizes[i] = assets[i][1] as int;
        _packs[i] = p;
        _offsets[i] = offset;
        offset += _sizes[i];
      }
    }
  }

  void clear() {
    _memory.clear();
    _bytes = 0;
  }

  void _trim() {
    while (_memory.isNotEmpty &&
        _bytes > MapImageBudget.shared.compressedBytes) {
      _bytes -= _memory.remove(_memory.keys.first)!.length;
    }
  }

  Future<void> prepare() async {
    if (kIsWeb) return;
    try {
      await (_index ??= _loadIndex());
    } catch (_) {
      _index = null;
      rethrow;
    }
  }

  Future<Uint8List> load(String key) async {
    if (kIsWeb) {
      final data = await rootBundle.load('assets/data/map_images/$key.webp');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    await prepare();
    final i = _locations['$key.webp'];
    if (i == null) throw StateError('Prepared map image missing: $key');
    final pack = _packs[i];
    var bytes = _memory.remove(pack);
    if (bytes != null) {
      _memory[pack] = bytes;
    } else {
      bytes = await _pending.putIfAbsent(pack, () async {
        try {
          final data = await rootBundle.load(_paths[pack]);
          final result = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          while (_memory.isNotEmpty &&
              _bytes + result.length > MapImageBudget.shared.compressedBytes) {
            _bytes -= _memory.remove(_memory.keys.first)!.length;
          }
          if (result.length <= MapImageBudget.shared.compressedBytes) {
            _memory[pack] = result;
            _bytes += result.length;
          }
          return result;
        } finally {
          _pending.remove(pack);
        }
      });
    }
    // Copy only one encoded image, so a decode cannot pin a whole evicted pack.
    return bytes.sublist(_offsets[i], _offsets[i] + _sizes[i]);
  }
}

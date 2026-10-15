import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offline-rendered GIS pyramid. No water geometry or DEM processing at runtime.
class GeographyTileIndex {
  GeographyTileIndex.fromJson(Map<String, dynamic> json)
    : layerMaxLevels = (json['layerMaxLevels'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)),
      available = (json['tiles'] as Map).keys.cast<String>().toSet(),
      maxLevel = json['maxLevel'] as int,
      detailLevels = (json['detailLevels'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as int),
      );
  final Set<String> available;
  final int maxLevel;
  final Map<String, int> detailLevels;
  final Map<String, int> layerMaxLevels;

  int layerLevel(int level, String layer) =>
      math.min(level, layerMaxLevels[layer] ?? level);

  bool hasTile(int level, int x, int y, String layer) {
    final lod = layerLevel(level, layer);
    final divisor = 1 << (level - lod);
    return available.contains('${lod}_${x ~/ divisor}_${y ~/ divisor}_$layer');
  }

  static Future<GeographyTileIndex>? _pending;
  static Future<GeographyTileIndex> load() async {
    try {
      return await (_pending ??= rootBundle
          .loadString('assets/data/map_tiles_uniform/index.json')
          .then((s) => GeographyTileIndex.fromJson(jsonDecode(s))));
    } catch (_) {
      _pending = null;
      rethrow;
    }
  }

  static double span(int level) => 4 / math.pow(2, level);
  static Rect geographicBounds(int level, int x, int y) {
    final side = span(level);
    return Rect.fromLTWH(120 + x * side, 48 - (y + 1) * side, side, side);
  }

  /// Use image resolution near the device's physical pixel density; overzoom the
  /// finest source instead of synthesizing geography during a gesture.
  int levelFor(double pixelsPerDegree, {String? prefectureId}) =>
      (math.log(pixelsPerDegree / 64) / math.ln2).ceil().clamp(
        0,
        detailLevels[prefectureId] ?? maxLevel,
      );
}

/// Shared bounded LRU. Active map tiles are pinned; in-flight decodes deduplicate.
class GeographyImageCache {
  GeographyImageCache({this.capacity = 48});
  static final shared = GeographyImageCache();
  final int capacity;
  final _images = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image>>{};
  final _pins = <Object, Set<String>>{};
  final _waiting = <Completer<void>>[];
  int _decoding = 0;
  Future<void> _acquire() async {
    if (_decoding < 2) {
      _decoding++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _decoding--;
    }
    _trim();
  }

  int get length => _images.length;
  ui.Image? peek(String key) {
    final image = _images.remove(key);
    if (image != null) _images[key] = image;
    return image;
  }

  void pin(Object owner, Set<String> keys) {
    _pins[owner] = keys;
    _trim();
  }

  void release(Object owner) {
    _pins.remove(owner);
    _trim();
  }

  void _trim() {
    final pinned = _pins.values.expand((s) => s).toSet();
    for (final key in _images.keys.toList()) {
      if (_images.length <= capacity) break;
      if (!pinned.contains(key)) _images.remove(key)!.dispose();
    }
  }

  Future<ui.Image> load(String key) {
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(key, () async {
      await _acquire();
      try {
        final bytes = await rootBundle.load(
          'assets/data/map_tiles_uniform/$key.webp',
        );
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        try {
          final image = (await codec.getNextFrame()).image;
          _images[key] = image;
          return image;
        } finally {
          codec.dispose();
        }
      } finally {
        _pending.remove(key);
        _release();
      }
    });
  }
}

class GeographyTiles extends StatefulWidget {
  const GeographyTiles({
    super.key,
    required this.transform,
    required this.project,
    required this.viewport,
    required this.clip,
    required this.enabled,
    this.prefectureId,
    this.nationalOverview = false,
  });
  final TransformationController transform;
  final Offset Function(math.Point<double>) project;
  final Size viewport;
  final Path clip;
  final bool enabled;
  final String? prefectureId;
  final bool nationalOverview;
  @override
  State<GeographyTiles> createState() => _GeographyTilesState();
}

class _GeographyTilesState extends State<GeographyTiles> {
  final cache = GeographyImageCache.shared;
  GeographyTileIndex? index;
  Timer? timer;
  int revision = 0;
  bool failed = false;
  bool loading = true;
  List<_Tile> tiles = [];
  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_schedule);
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final loaded = await GeographyTileIndex.load();
      if (!mounted) return;
      index = loaded;
      _refresh();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void didUpdateWidget(GeographyTiles old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_schedule);
      widget.transform.addListener(_schedule);
    }
    if (old.transform != widget.transform ||
        old.project != widget.project ||
        old.viewport != widget.viewport ||
        old.clip != widget.clip ||
        old.enabled != widget.enabled ||
        old.prefectureId != widget.prefectureId ||
        old.nationalOverview != widget.nationalOverview) {
      _schedule();
    }
  }

  void _schedule() {
    // Coalesce pinch/pan events. The existing raster remains on screen meanwhile.
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 70), _refresh);
  }

  Rect _sceneRect(int level, int x, int y) {
    final geo = GeographyTileIndex.geographicBounds(level, x, y);
    return Rect.fromPoints(
      widget.project(math.Point(geo.left, geo.bottom)),
      widget.project(math.Point(geo.right, geo.top)),
    );
  }

  Future<void> _refresh() async {
    final manifest = index;
    if (!mounted || manifest == null) return;
    final token = ++revision;
    if (!widget.enabled) {
      cache.pin(this, {});
      setState(() {
        tiles = [];
        loading = false;
      });
      return;
    }
    final origin = widget.project(const math.Point(120.0, 48.0));
    final unit = widget.project(const math.Point(121.0, 47.0)) - origin;
    final zoom = widget.transform.value.getMaxScaleOnAxis();
    var level = manifest.levelFor(
      math.max(unit.dx.abs(), unit.dy.abs()) *
          zoom *
          math.min(1.5, MediaQuery.devicePixelRatioOf(context)),
      prefectureId: widget.prefectureId,
    );
    final scene = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    );
    final detailLayer = widget.nationalOverview ? 'overview' : 'detail';
    List<(int, int)> visible(int lod) {
      final span = GeographyTileIndex.span(lod);
      final margin = span * math.max(unit.dx.abs(), unit.dy.abs());
      final view = scene.inflate(margin).intersect(widget.clip.getBounds());
      if (view.isEmpty) return [];
      final xmin = ((view.left - origin.dx) / unit.dx / span).floor();
      final xmax = ((view.right - origin.dx) / unit.dx / span).floor();
      final ymin = ((view.top - origin.dy) / unit.dy / span).floor();
      final ymax = ((view.bottom - origin.dy) / unit.dy / span).floor();
      return [
        for (var x = xmin; x <= xmax; x++)
          for (var y = ymin; y <= ymax; y++)
            if (manifest.hasTile(lod, x, y, 'shade') ||
                manifest.hasTile(lod, x, y, detailLayer))
              (x, y),
      ];
    }

    var cells = visible(level);
    // Keep requests/memory bounded even on a very large or high-DPI viewport.
    while (cells.length > 12 && level > 0) {
      cells = visible(--level);
    }
    final wanted = <String>{};
    final descriptors = <(String, Rect, String, Rect)>[];
    for (final (x, y) in cells) {
      final target = _sceneRect(level, x, y);
      for (final layer in ['shade', detailLayer]) {
        final sourceLevel = manifest.layerLevel(level, layer);
        if (!manifest.hasTile(level, x, y, layer)) continue;
        // Parent images fill the target until its sharper tile arrives.
        for (final lod in [sourceLevel, if (sourceLevel > 0) 0]) {
          final divisor = 1 << (level - lod);
          final parent = '${lod}_${x ~/ divisor}_${y ~/ divisor}_$layer';
          if (!manifest.available.contains(parent)) continue;
          wanted.add(parent);
          descriptors.add((
            parent,
            _sceneRect(lod, x ~/ divisor, y ~/ divisor),
            layer,
            target,
          ));
        }
      }
    }
    cache.pin(this, wanted);
    void publish() {
      if (!mounted || token != revision) return;
      // Descriptors are sharpest-first, one image per target/layer.
      final chosen = <(Rect, String)>{};
      final ready = <_Tile>[];
      for (final (key, rect, layer, target) in descriptors) {
        final image = cache.peek(key);
        if (image == null || !chosen.add((target, layer))) continue;
        ready.add(_Tile(image, rect, target, layer));
      }
      final changed =
          ready.length != tiles.length ||
          Iterable<int>.generate(
            ready.length,
          ).any((i) => !ready[i].same(tiles[i]));
      if (changed) setState(() => tiles = ready);
    }

    publish();
    final missing =
        wanted.where((key) => cache.peek(key) == null).toList()
          ..sort((a, b) => a.compareTo(b)); // low-resolution coverage first
    if (missing.isNotEmpty && !loading) setState(() => loading = true);
    for (var start = 0; start < missing.length; start += 2) {
      if (!mounted || token != revision) return;
      final results = await Future.wait(
        missing.skip(start).take(2).map((key) async {
          try {
            await cache.load(key);
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      if (!mounted || token != revision) return;
      failed = results.contains(false) || failed;
      publish();
    }
    cache.pin(this, wanted);
    if (mounted && token == revision) setState(() => loading = false);
  }

  @override
  void dispose() {
    revision++;
    timer?.cancel();
    widget.transform.removeListener(_schedule);
    cache.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        !widget.enabled
            ? '背景地図は非表示'
            : failed
            ? '背景地図の読込失敗'
            : loading
            ? '背景地図を読み込み中'
            : '背景地図の読込完了',
    child: AnimatedBuilder(
      animation: widget.transform,
      builder:
          (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final visible = Rect.fromPoints(
                widget.transform.toScene(Offset.zero),
                widget.transform.toScene(
                  widget.viewport.bottomRight(Offset.zero),
                ),
              ).intersect(Offset.zero & constraints.biggest);
              if (visible.isEmpty) return const SizedBox();
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: visible,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _GeographyPainter(
                          widget.enabled ? tiles : [],
                          widget.clip,
                          visible.topLeft,
                        ),
                      ),
                    ),
                  ),
                  if (failed)
                    Positioned.fromRect(
                      rect: visible,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Transform.scale(
                          alignment: Alignment.topLeft,
                          scale: 1 / widget.transform.value.getMaxScaleOnAxis(),
                          child: TextButton(
                            onPressed: () {
                              failed = false;
                              index == null ? _loadIndex() : _refresh();
                            },
                            child: const Text('背景地図の読込を再試行'),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    ),
  );
}

class _Tile {
  _Tile(this.image, this.rect, this.target, this.layer);
  final ui.Image image;
  final Rect rect, target;
  final String layer;
  bool same(_Tile other) =>
      identical(image, other.image) &&
      rect == other.rect &&
      target == other.target &&
      layer == other.layer;
}

class _GeographyPainter extends CustomPainter {
  _GeographyPainter(this.tiles, this.clip, this.origin);
  final Offset origin;
  final List<_Tile> tiles;
  final Path clip;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-origin.dx, -origin.dy);
    canvas.clipPath(clip);
    for (final layer in ['shade', 'detail', 'overview']) {
      for (final tile in tiles.where((t) => t.layer == layer)) {
        canvas.save();
        canvas.clipRect(tile.target);
        canvas.drawImageRect(
          tile.image,
          Rect.fromLTWH(
            0,
            0,
            tile.image.width.toDouble(),
            tile.image.height.toDouble(),
          ),
          tile.rect,
          Paint()
            ..filterQuality = FilterQuality.low
            ..blendMode = BlendMode.srcOver,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GeographyPainter old) =>
      old.tiles != tiles || old.clip != clip || old.origin != origin;
}

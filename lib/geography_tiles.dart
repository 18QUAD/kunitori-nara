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
      minLevel = json['minLevel'] as int? ?? 0,
      basePixelsPerDegree = json['basePixelsPerDegree'] as int? ?? 64,
      detailLevels = (json['detailLevels'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as int),
      );
  final Set<String> available;
  final int maxLevel;
  final int minLevel;
  final int basePixelsPerDegree;
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
  static Future<GeographyTileIndex>? _borderPending;
  static Future<GeographyTileIndex> loadBorders() async {
    try {
      return await (_borderPending ??= rootBundle
          .loadString('assets/data/border_tiles/index-plain.json', cache: false)
          .then((s) => GeographyTileIndex.fromJson(jsonDecode(s))));
    } catch (_) {
      _borderPending = null;
      rethrow;
    }
  }

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
      (math.log(pixelsPerDegree / basePixelsPerDegree) / math.ln2).ceil().clamp(
        minLevel,
        detailLevels[prefectureId] ?? maxLevel,
      );
}

/// Shared bounded LRU. Active map tiles are pinned; in-flight decodes deduplicate.
class GeographyImageCache {
  GeographyImageCache({
    this.capacity = 48,
    this.assetDirectory = 'assets/data/map_tiles_uniform',
    this.filenamePrefix = '',
  });
  static final shared = GeographyImageCache();
  static final borders = GeographyImageCache(
    capacity: 8,
    assetDirectory: 'assets/data/border_tiles',
    filenamePrefix: 'plain_',
  );
  final int capacity;
  final String assetDirectory, filenamePrefix;
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
          '$assetDirectory/$filenamePrefix$key.webp',
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
    this.boundaryLayer,
  });
  final TransformationController transform;
  final Offset Function(math.Point<double>) project;
  final Size viewport;
  final Path clip;
  final bool enabled;
  final String? prefectureId;
  final bool nationalOverview;
  final String? boundaryLayer;
  @override
  State<GeographyTiles> createState() => _GeographyTilesState();
}

class _GeographyTilesState extends State<GeographyTiles> {
  late final cache =
      widget.boundaryLayer == null
          ? GeographyImageCache.shared
          : GeographyImageCache.borders;
  GeographyTileIndex? index;
  Timer? timer;
  int revision = 0;
  double? refreshedZoom;
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
      final loaded =
          await (widget.boundaryLayer == null
              ? GeographyTileIndex.load()
              : GeographyTileIndex.loadBorders());
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
        old.nationalOverview != widget.nationalOverview ||
        old.boundaryLayer != widget.boundaryLayer) {
      _schedule();
    }
  }

  void _schedule() {
    timer?.cancel();
    // Never stretch the previous border LOD for a debounce frame. Refresh the
    // exact LOD synchronously on scale changes; cached tiles appear immediately.
    if (widget.boundaryLayer != null &&
        widget.transform.value.getMaxScaleOnAxis() != refreshedZoom) {
      _refresh();
      return;
    }
    // Panning and terrain images can keep their current raster while coalescing.
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
    final borders = widget.boundaryLayer != null;
    refreshedZoom = zoom;
    var level = manifest.levelFor(
      math.max(unit.dx.abs(), unit.dy.abs()) *
          zoom *
          math.min(borders ? 3.0 : 1.5, MediaQuery.devicePixelRatioOf(context)),
      prefectureId: widget.prefectureId,
    );
    final scene = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    );
    final detailLayer = widget.nationalOverview ? 'overview' : 'detail';
    final layers =
        widget.boundaryLayer == null
            ? ['shade', detailLayer]
            : [widget.boundaryLayer!];
    List<(int, int)> visible(int lod) {
      final span = GeographyTileIndex.span(lod);
      // Thin boundaries need native display resolution. Loading a whole ring
      // of offscreen border tiles used to exceed the cell budget and downgrade
      // even small phone viewports by several image levels.
      final margin =
          borders ? 0.0 : span * math.max(unit.dx.abs(), unit.dy.abs());
      final view = scene.inflate(margin).intersect(widget.clip.getBounds());
      if (view.isEmpty) return [];
      final xmin = ((view.left - origin.dx) / unit.dx / span).floor();
      final xmax = ((view.right - origin.dx) / unit.dx / span).floor();
      final ymin = ((view.top - origin.dy) / unit.dy / span).floor();
      final ymax = ((view.bottom - origin.dy) / unit.dy / span).floor();
      return [
        for (var x = xmin; x <= xmax; x++)
          for (var y = ymin; y <= ymax; y++)
            if (layers.any((layer) => manifest.hasTile(lod, x, y, layer)))
              (x, y),
      ];
    }

    var cells = visible(level);
    // Keep requests/memory bounded even on a very large or high-DPI viewport.
    // 24 x 512px bounds the sharp border surface at 24 MiB, plus parents.
    // Offscreen images still use the small shared LRU rather than staying pinned.
    final cellLimit = borders ? 24 : 12;
    while (cells.length > cellLimit && level > manifest.minLevel) {
      cells = visible(--level);
    }
    final wanted = <String>{};
    final descriptors = <(String, Rect, String, Rect)>[];
    for (final (x, y) in cells) {
      final target = _sceneRect(level, x, y);
      for (final layer in layers) {
        final sourceLevel = manifest.layerLevel(level, layer);
        if (!manifest.hasTile(level, x, y, layer)) continue;
        // Only terrain may use coarse parents. Enlarged border parents would
        // briefly show much thicker strokes while sharp tiles are loading.
        final fallback =
            widget.boundaryLayer == null ? manifest.minLevel : sourceLevel;
        for (final lod in [sourceLevel, if (sourceLevel > fallback) fallback]) {
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

  String get statusLabel =>
      widget.boundaryLayer != null
          ? (failed
              ? '境界線画像の読込失敗'
              : loading
              ? '境界線画像を読み込み中'
              : '境界線画像の読込完了')
          : !widget.enabled
          ? '背景地図は非表示'
          : failed
          ? '背景地図の読込失敗'
          : loading
          ? '背景地図を読み込み中'
          : '背景地図の読込完了';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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
                // A full-map leaf semantics node receives browser pointer
                // events even when the painted image uses IgnorePointer.
                // Keep the status accessible in a one-screen-pixel corner.
                Positioned(
                  left: visible.left,
                  top: visible.top,
                  width: 1 / widget.transform.value.getMaxScaleOnAxis(),
                  height: 1 / widget.transform.value.getMaxScaleOnAxis(),
                  child: Semantics(
                    container: true,
                    label: statusLabel,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fromRect(
                  rect: visible,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GeographyPainter(
                          widget.enabled ? tiles : [],
                          widget.clip,
                          visible.topLeft,
                        ),
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
                          child: Text(
                            widget.boundaryLayer == null
                                ? '背景地図の読込を再試行'
                                : '境界線の読込を再試行',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
    for (final layer in [
      'shade',
      'detail',
      'overview',
      'pref',
      'city',
      'town',
    ]) {
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

import 'diagnostics.dart';
import 'map_image_budget.dart';
import 'prepared_map_bytes.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One button step equals one prepared image level. Fixed 2x sampling makes
/// the pre-baked .625 logical-pixel boundary independent of device DPR.
abstract final class MapImageScale {
  static const sampling = 2.0;
  static const minLevel = -3;
  static int maximum({bool national = false, bool city = false}) =>
      national
          ? 5
          : city
          ? 8
          : 7;
  static double scale(int level, double projection) =>
      128 * math.pow(2, level) / (projection * sampling);
  static int level(double zoom, double projection) =>
      (math.log(zoom * projection * sampling / 128) / math.ln2).round();
  static double snap(
    double zoom,
    double projection,
    int maximum, {
    bool fit = false,
  }) {
    final exponent = math.log(zoom * projection * sampling / 128) / math.ln2;
    final level = (fit ? exponent.floor() : exponent.round()).clamp(
      minLevel,
      maximum,
    );
    return scale(level, projection);
  }
}

class GeographyTileIndex {
  GeographyTileIndex.fromJson(Map<String, dynamic> json)
    : layerMaxLevels = (json['layerMaxLevels'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      ),
      available = (json['tiles'] as Map).keys.cast<String>().toSet(),
      maxLevel = json['maxLevel'] as int,
      minLevel = json['minLevel'] as int,
      basePixelsPerDegree = json['basePixelsPerDegree'] as int;
  final Set<String> available;
  final int maxLevel, minLevel, basePixelsPerDegree;
  final Map<String, int> layerMaxLevels;
  int layerLevel(int level, String layer) =>
      math.min(level, layerMaxLevels[layer] ?? maxLevel);
  bool hasTile(int level, int x, int y, String layer) =>
      available.contains('${level}_${x}_${y}_$layer');
  static Future<GeographyTileIndex>? _pending;
  static Future<GeographyTileIndex> loadBorders() => load();
  static Future<GeographyTileIndex> load() async {
    try {
      return await (_pending ??= rootBundle
          .loadString('assets/data/map_images/index.json', cache: false)
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

  int levelFor(double pixelsPerDegree, {String? prefectureId}) =>
      (math.log(pixelsPerDegree / basePixelsPerDegree) / math.ln2)
          .round()
          .clamp(minLevel, maxLevel);
}

/// Navigation waits for pending decodes but retains reusable finished images.
/// Reclamation happens only under the shared budget, or OS memory pressure.
Future<void> retireMapImages() async {
  await GeographyImageCache.shared.drain();
  GeographyImageCache.shared.trim();
}

/// One byte-bounded LRU for backgrounds AND boundaries, including reservations
/// for decodes in flight. Active painters pin their images until the next frame.
class GeographyImageCache {
  GeographyImageCache({this.capacity = 256});
  static final shared = GeographyImageCache();
  final int capacity;
  final _images = <String, ui.Image>{};
  final _reservations = <String, Object>{};
  final _pending = <String, Future<ui.Image>>{};
  final _pins = <Object, Set<String>>{};
  final _preferred = <Object, Set<String>>{};
  final _waiting = <Completer<void>>[];
  int _decoding = 0;
  int _decodeCount = 0;
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
  }

  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait([
        for (final f in _pending.values.toList())
          f.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ]);
    }
  }

  int get length => _images.length;
  Map<String, Object?> get diagnosticCounts => {
    'images': length,
    'bytes': _images.values.fold<int>(0, (n, i) => n + i.width * i.height * 4),
    'budget': MapImageBudget.shared.diagnosticCounts,
    'decoding': _decoding,
    'queued': _waiting.length,
    'owners': _pins.length,
    'decodes': _decodeCount,
    'runtimeRasters': 0,
  };
  ui.Image? peek(String key) {
    final image = _images.remove(key);
    if (image != null) _images[key] = image;
    return image;
  }

  void pin(Object owner, Set<String> keys) {
    _pins[owner] = keys;
  }

  void prefer(Object owner, Set<String> keys) {
    _preferred[owner] = keys;
  }

  void release(Object owner) {
    _pins.remove(owner);
    _preferred.remove(owner);
    trim();
  }

  void _remove(String key) {
    _images.remove(key)?.dispose();
    MapImageBudget.shared.release(_reservations.remove(key));
  }

  void clearUnused() {
    PreparedMapBytes.shared.clear();
    final pinned = _pins.values.expand((s) => s).toSet();
    for (final key in _images.keys.toList()) {
      if (!pinned.contains(key)) _remove(key);
    }
  }

  void trim([int incoming = 0]) {
    final budget = MapImageBudget.shared;
    final pinned = _pins.values.expand((s) => s).toSet();
    final preferred = _preferred.values.expand((s) => s).toSet();
    final keys = [
      ..._images.keys.where((key) => !preferred.contains(key)),
      ..._images.keys.where(preferred.contains),
    ];
    for (final key in keys) {
      if (budget.retainedBytes + incoming <=
              budget.limit(MapImageKind.source) &&
          length < capacity + (incoming == 0 ? 1 : 0)) {
        break;
      }
      if (!pinned.contains(key)) _remove(key);
    }
  }

  bool get canPrefetch {
    if (_pending.isNotEmpty) return false;
    final preferred = _preferred.values.expand((s) => s).toSet();
    final pinned = _pins.values.expand((s) => s).toSet();
    final reclaimable = _images.entries.where(
      (e) => !preferred.contains(e.key) && !pinned.contains(e.key),
    );
    final reclaimBytes = reclaimable.fold(
      0,
      (n, e) => n + e.value.width * e.value.height * 4,
    );
    return length - reclaimable.length < capacity &&
        MapImageBudget.shared.retainedBytes -
                reclaimBytes +
                MapImageBudget.mib <=
            MapImageBudget.shared.limit(MapImageKind.source);
  }

  Future<ui.Image> load(String key) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(key, () async {
      await _acquire();
      final reservation = Object();
      var retained = false;
      try {
        final parts = key.split('~');
        final side = parts.length == 1 ? 512 : int.parse(parts.last);
        final bytesNeeded = side * side * 4;
        trim(bytesNeeded);
        final kind =
            parts.first.endsWith('_background') ||
                    parts.first.endsWith('_overview')
                ? MapImageKind.background
                : MapImageKind.boundary;
        if (!MapImageBudget.shared.reserve(reservation, kind, bytesNeeded)) {
          throw StateError('Map image budget exhausted');
        }
        final bytes = await PreparedMapBytes.shared.load(parts.first);
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: side,
          targetHeight: side,
        );
        try {
          final image = (await codec.getNextFrame()).image;
          if (image.width != side || image.height != side) {
            image.dispose();
            throw StateError('Unexpected map image dimensions');
          }
          _images[key] = image;
          _reservations[key] = reservation;
          retained = true;
          _decodeCount++;
          return image;
        } finally {
          codec.dispose();
        }
      } finally {
        if (!retained) MapImageBudget.shared.release(reservation);
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
    this.onBusyChanged,
  });
  final TransformationController transform;
  final Offset Function(math.Point<double>) project;
  final Size viewport;
  final Path clip;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  final String? prefectureId;
  final bool nationalOverview;
  final String? boundaryLayer;
  @override
  State<GeographyTiles> createState() => _GeographyTilesState();
}

class _GeographyTilesState extends State<GeographyTiles> {
  final cache = GeographyImageCache.shared;
  GeographyTileIndex? index;
  Timer? timer, _retryTimer;
  int revision = 0, _retryAttempt = 0;
  bool _refreshing = false, _refreshPending = false;
  double? refreshedZoom;
  bool failed = false, loading = true;
  List<_Tile> tiles = [];
  Set<String> _pinned = {};

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_schedule);
    MapImageBudget.shared.addListener(_budgetChanged);
    _loadIndex();
  }

  void _budgetChanged() {
    cache.trim();
    _refresh();
  }

  Future<void> _loadIndex() async {
    try {
      final manifest = await GeographyTileIndex.load();
      if (!mounted) return;
      index = manifest;
      _refresh();
    } catch (error) {
      if (!mounted) return;
      recordDiagnostic('images_index_error', {'error': error.toString()});
      setState(() => failed = true);
      widget.onBusyChanged?.call(false);
      _retry();
    }
  }

  void _retry() {
    if (!mounted || !widget.enabled || _retryTimer != null) return;
    _retryTimer = Timer(
      Duration(seconds: math.min(30, 1 << math.min(_retryAttempt++, 5))),
      () {
        _retryTimer = null;
        if (!mounted) return;
        index == null ? _loadIndex() : _refresh();
      },
    );
  }

  @override
  void didUpdateWidget(GeographyTiles old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_schedule);
      widget.transform.addListener(_schedule);
    }
    // Ownership/progress/labels are deliberately absent from this dependency
    // list. They never invalidate an image or initiate background work.
    if (old.transform != widget.transform ||
        old.project != widget.project ||
        old.viewport != widget.viewport ||
        old.clip != widget.clip ||
        old.enabled != widget.enabled ||
        old.nationalOverview != widget.nationalOverview ||
        old.boundaryLayer != widget.boundaryLayer) {
      _schedule();
    }
  }

  void _schedule() {
    revision++;
    timer?.cancel();
    // Coalesce pinch/pan. The painter hides outdated borders immediately, so
    // an old thin line is never stretched into a thick transient outline.
    if (index != null &&
        widget.transform.value.getMaxScaleOnAxis() != refreshedZoom) {
      final a = widget.project(const math.Point(120.0, 48.0));
      final b = widget.project(const math.Point(121.0, 47.0));
      final zoom = widget.transform.value.getMaxScaleOnAxis();
      final snapped = MapImageScale.scale(_level, (b.dy - a.dy).abs());
      if ((zoom - snapped).abs() < 1e-8) {
        _refresh();
        return;
      }
    }
    timer = Timer(const Duration(milliseconds: 70), _refresh);
  }

  Rect _sceneRect(int level, int x, int y) {
    final geo = GeographyTileIndex.geographicBounds(level, x, y);
    return Rect.fromPoints(
      widget.project(math.Point(geo.left, geo.bottom)),
      widget.project(math.Point(geo.right, geo.top)),
    );
  }

  List<(String, Rect, Rect)> _descriptors(int level) {
    final manifest = index!;
    final layer =
        widget.boundaryLayer ??
        (widget.nationalOverview ? 'overview' : 'background');
    level = manifest
        .layerLevel(level, layer)
        .clamp(manifest.minLevel, manifest.maxLevel);
    final scene = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    ).intersect(widget.clip.getBounds());
    if (scene.isEmpty) return [];
    final origin = widget.project(const math.Point(120.0, 48.0));
    final unit = widget.project(const math.Point(121.0, 47.0)) - origin;
    final span = GeographyTileIndex.span(level);
    final result = <(String, Rect, Rect)>[];
    final xmin = ((scene.left - origin.dx) / unit.dx / span).floor();
    final xmax = ((scene.right - origin.dx) / unit.dx / span).floor();
    final ymin = ((scene.top - origin.dy) / unit.dy / span).floor();
    final ymax = ((scene.bottom - origin.dy) / unit.dy / span).floor();
    for (var x = xmin; x <= xmax; x++) {
      for (var y = ymin; y <= ymax; y++) {
        final target = _sceneRect(level, x, y);
        var lod = level, sx = x, sy = y;
        // Fine dry patches reuse the same prepared background. Water-containing
        // patches always have their own fine bitmap. Borders never use parents.
        while (true) {
          final key = '${lod}_${sx}_${sy}_$layer';
          if (manifest.available.contains(key)) {
            result.add((key, _sceneRect(lod, sx, sy), target));
            break;
          }
          if (layer != 'background' || lod <= 5) break;
          lod--;
          sx = (sx / 2).floor();
          sy = (sy / 2).floor();
        }
      }
    }
    // Wide desktop windows can cover more cells than a phone. Decode finished
    // tiles smaller there, without changing image level or border screen width.
    var side = 512;
    final count = result.map((d) => d.$1).toSet().length;
    while (side > 128 &&
        count * side * side * 4 >
            MapImageBudget.shared.limit(MapImageKind.source) ~/ 2) {
      side ~/= 2;
    }
    return side == 512
        ? result
        : [
          for (final (key, rect, target) in result)
            ('$key~$side', rect, target),
        ];
  }

  int get _level {
    final a = widget.project(const math.Point(120.0, 48.0));
    final b = widget.project(const math.Point(121.0, 47.0));
    return MapImageScale.level(
      widget.transform.value.getMaxScaleOnAxis(),
      (b.dy - a.dy).abs(),
    ).clamp(index!.minLevel, index!.maxLevel);
  }

  Future<void> _refresh() async {
    if (!mounted || index == null) return;
    revision++;
    _refreshPending = true;
    if (_refreshing) return;
    _refreshing = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    widget.onBusyChanged?.call(true);
    recordDiagnostic('images_load_start', {
      'imageScale': widget.transform.value.getMaxScaleOnAxis(),
      'imageCache': cache.diagnosticCounts,
    });
    try {
      do {
        _refreshPending = false;
        failed = false;
        await _refreshOnce();
        await WidgetsBinding.instance.endOfFrame;
      } while (mounted && _refreshPending);
    } catch (error) {
      recordDiagnostic('images_load_error', {'error': error.toString()});
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    } finally {
      _refreshing = false;
      recordDiagnostic('images_load_end', {
        'imageCache': cache.diagnosticCounts,
      });
      if (mounted) {
        widget.onBusyChanged?.call(false);
        if (failed) {
          _retry();
        } else {
          _retryAttempt = 0;
        }
      }
    }
  }

  Future<void> _refreshOnce() async {
    final token = revision;
    final level = _level;
    final descriptors =
        widget.enabled ? _descriptors(level) : <(String, Rect, Rect)>[];
    final wanted = descriptors.map((d) => d.$1).toSet();
    final adjacentKeys = <String>{
      if (widget.enabled)
        for (final adjacent in [level - 1, level + 1])
          if (adjacent >= index!.minLevel && adjacent <= index!.maxLevel)
            ..._descriptors(adjacent).map((d) => d.$1),
    };
    cache.prefer(this, {...wanted, ...adjacentKeys});
    cache.pin(this, {..._pinned, ...wanted});
    refreshedZoom = widget.transform.value.getMaxScaleOnAxis();
    void publish() {
      if (!mounted || token != revision) return;
      setState(() {
        tiles = [
          for (final (key, rect, target) in descriptors)
            if (cache.peek(key) case final image?)
              _Tile(image, rect, target, widget.boundaryLayer ?? 'background'),
        ];
        loading = tiles.length != descriptors.length;
      });
    }

    publish();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || token != revision) return;
    // The old paint has retired; only now may the LRU evict departing pixels.
    _pinned = wanted;
    cache.pin(this, wanted);
    for (final key in wanted) {
      if (!mounted || token != revision) return;
      await cache.load(key);
      publish();
    }
    if (!mounted || token != revision) return;
    // Prefetch nearest levels only into spare capacity. It never evicts a
    // visible image or replaces a warm adjacent level just to fill the budget.
    for (final key in adjacentKeys) {
      if (!mounted || token != revision || !cache.canPrefetch) return;
      if (cache.peek(key) == null) await cache.load(key);
    }
  }

  @override
  void dispose() {
    revision++;
    timer?.cancel();
    _retryTimer?.cancel();
    widget.transform.removeListener(_schedule);
    MapImageBudget.shared.removeListener(_budgetChanged);
    // Keep references pinned until the outgoing display list has retired.
    WidgetsBinding.instance.addPostFrameCallback((_) => cache.release(this));
    WidgetsBinding.instance.ensureVisualUpdate();
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
                          widget.enabled &&
                                  widget.transform.value.getMaxScaleOnAxis() ==
                                      refreshedZoom
                              ? tiles
                              : [],
                          widget.clip,
                          visible.topLeft,
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
    for (final tile in tiles) {
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GeographyPainter old) =>
      old.tiles != tiles || old.clip != clip || old.origin != origin;
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'prefecture_border_mesh.dart';
import 'water_mesh.dart';

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
          .loadString('assets/data/border_tiles/index-slim.json', cache: false)
          .then((s) => GeographyTileIndex.fromJson(jsonDecode(s))));
    } catch (_) {
      _borderPending = null;
      rethrow;
    }
  }

  static Future<GeographyTileIndex> load() async {
    try {
      return await (_pending ??= rootBundle
          .loadString('assets/data/map_tiles_uniform/index-dry.json')
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

// Both layers and departing map widgets share one native raster queue. A
// completed load must retire its images before another map allocates replacements.
final _retirements = <Future<void>>{};
Future<void>? _rasterTail;
Future<void> _serialRaster(Future<void> Function() action) {
  Future<void> run() async {
    await Future.wait(_retirements.toList());
    await action();
  }

  final previous = _rasterTail;
  final result = previous == null ? run() : previous.then((_) => run());
  late final Future<void> tail;
  void finish() {
    if (identical(_rasterTail, tail)) _rasterTail = null;
  }

  tail = result.then<void>(
    (_) => finish(),
    onError: (Object _, StackTrace __) => finish(),
  );
  _rasterTail = tail;
  return result;
}

/// Shared bounded LRU. Active map tiles are pinned; in-flight decodes deduplicate.
class GeographyImageCache {
  GeographyImageCache({
    this.capacity = 48,
    this.assetDirectory = 'assets/data/map_tiles_uniform',
    this.filenamePrefix = '',
    this.layerFilenamePrefixes = const {'detail': 'dry_', 'overview': 'dry_'},
  });
  static final shared = GeographyImageCache(
    layerFilenamePrefixes: const {'detail': 'dry_', 'overview': 'dry_'},
  );
  static final borders = GeographyImageCache(
    capacity: 8,
    assetDirectory: 'assets/data/border_tiles',
    filenamePrefix: 'slim_',
    layerFilenamePrefixes: const {'pref': 'slimshared_'},
  );
  final int capacity;
  final String assetDirectory, filenamePrefix;
  final Map<String, String> layerFilenamePrefixes;
  String prefixFor(String key) =>
      layerFilenamePrefixes[key.split('_').last] ?? filenamePrefix;
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

  void clearUnused() {
    final pinned = _pins.values.expand((keys) => keys).toSet();
    for (final key in _images.keys.toList()) {
      if (!pinned.contains(key)) _images.remove(key)!.dispose();
    }
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
          '$assetDirectory/${prefixFor(key)}$key.webp',
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
    this.boundaryPaths,
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

  /// Detailed outlines already resident for the visible prefecture. Cached as
  /// images with the same screen stroke width at every scale.
  final Iterable<Path>? boundaryPaths;
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
  bool _refreshing = false;
  bool _refreshPending = false;
  double? refreshedZoom;
  bool failed = false;
  bool loading = true;
  List<_Tile> tiles = [];
  final _detailImages = <String, ui.Image>{};
  Future<PrefectureBorderMesh>? _mesh;
  Future<WaterMesh>? _waterMesh;

  Future<void> _disposeImages(Iterable<ui.Image> images) async {
    final retired = images.toList();
    if (retired.isEmpty) return;
    final complete = Completer<void>();
    _retirements.add(complete.future);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final image in retired) {
        image.dispose();
      }
      _retirements.remove(complete.future);
      complete.complete();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    await complete.future;
  }

  void _clearDetailImages() {
    revision++;
    tiles = [];
    unawaited(_disposeImages(_detailImages.values));
    _detailImages.clear();
    _mesh = null;
    _waterMesh = null;
  }

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
      if (mounted) {
        setState(() => failed = true);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  void didUpdateWidget(GeographyTiles old) {
    super.didUpdateWidget(old);
    if (old.clip != widget.clip ||
        old.project != widget.project ||
        old.boundaryLayer != widget.boundaryLayer ||
        old.prefectureId != widget.prefectureId ||
        old.nationalOverview != widget.nationalOverview) {
      _clearDetailImages();
    }
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
    if (widget.transform.value.getMaxScaleOnAxis() != refreshedZoom) {
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
    if (!mounted || index == null) return;
    // Invalidate stale results immediately, but let their native work finish
    // before starting the latest requested view. Keep only one pending request.
    revision++;
    _refreshPending = true;
    if (_refreshing) {
      if (widget.transform.value.getMaxScaleOnAxis() != refreshedZoom) {
        setState(() => tiles = []);
      }
      return;
    }
    _refreshing = true;
    widget.onBusyChanged?.call(true);
    try {
      do {
        _refreshPending = false;
        await _refreshOnce();
        // Retired images are disposed after paint; don't unlock beforehand.
        await WidgetsBinding.instance.endOfFrame;
      } while (mounted && _refreshPending);
    } finally {
      _refreshing = false;
      if (mounted) widget.onBusyChanged?.call(false);
    }
  }

  Future<void> _refreshOnce() async {
    final manifest = index;
    if (!mounted || manifest == null) return;
    final token = ++revision;
    if (!widget.enabled) {
      cache.pin(this, {});
      _clearDetailImages();
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
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    if (borders &&
        (widget.boundaryPaths != null || widget.boundaryLayer == 'pref')) {
      try {
        await _refreshDetailImages(token, zoom, pixelRatio);
      } catch (_) {
        if (mounted && token == revision) {
          setState(() {
            failed = true;
            loading = false;
          });
        }
      }
      return;
    }
    if (!borders) {
      final (_, _, _, cells) = _rasterGrid(zoom, pixelRatio);
      setState(() {
        tiles = [
          for (final (key, rect) in cells)
            if (_detailImages[key] case final image?)
              _Tile(image, rect, rect, 'background'),
        ];
        loading = tiles.length != cells.length;
      });
      if (!loading && !failed) {
        cache.pin(this, {});
        return;
      }
    }
    var level = manifest.levelFor(
      math.max(unit.dx.abs(), unit.dy.abs()) *
          zoom *
          math.min(borders ? 3.0 : 1.5, MediaQuery.devicePixelRatioOf(context)),
      prefectureId: widget.prefectureId,
    );
    var scene = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    );
    if (!borders) {
      final (_, _, _, cells) = _rasterGrid(zoom, pixelRatio);
      if (cells.isNotEmpty) {
        scene = cells
            .map((cell) => cell.$2)
            .reduce((a, b) => a.expandToInclude(b));
      }
    }
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
    final cellLimit = 24;
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
    var backgroundTiles = <_Tile>[];
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
      if (!borders) {
        backgroundTiles = ready;
        return;
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
    if (!mounted || token != revision) return;
    if (!borders) {
      if (failed) {
        setState(() => loading = false);
        return;
      }
      try {
        await _refreshDetailImages(
          token,
          zoom,
          pixelRatio,
          background: backgroundTiles,
        );
      } catch (_) {
        if (mounted && token == revision) {
          setState(() {
            failed = true;
            loading = false;
          });
        }
      }
      if (mounted && token == revision) cache.pin(this, {});
    } else {
      setState(() => loading = false);
    }
  }

  (int, double, double, List<(String, Rect)>) _rasterGrid(
    double zoom,
    double dpr,
  ) {
    // Sixteen image scales per doubling keep the apparent line within 4.3%
    // of 0.65 logical pixels, including between the +/- button scales.
    final exponent = (math.log(zoom) / math.ln2 * 16).ceil();
    final renderZoom = math.pow(2, exponent / 16).toDouble();
    Rect scene = Rect.fromPoints(
      widget.transform.toScene(Offset.zero),
      widget.transform.toScene(widget.viewport.bottomRight(Offset.zero)),
    ).intersect(widget.clip.getBounds());
    List<(String, Rect)> cells(double density) {
      if (scene.isEmpty) return [];
      final side = 512 / density;
      return [
        for (
          var x = (scene.left / side).floor();
          x <= (scene.right / side).floor();
          x++
        )
          for (
            var y = (scene.top / side).floor();
            y <= (scene.bottom / side).floor();
            y++
          )
            (
              '$exponent@$density:$x:$y',
              Rect.fromLTWH(x * side, y * side, side, side),
            ),
      ];
    }

    var density = renderZoom * dpr;
    var wanted = cells(density);
    final imageLimit = widget.boundaryLayer == null ? 12 : 24;
    while (wanted.length > imageLimit) {
      density /= 2;
      wanted = cells(density);
    }
    return (exponent, renderZoom, density, wanted);
  }

  // Rasterize only on a cache miss, never in paint() or on a game tap. Fixed
  // 512px cells and quantized scale keep both the work and native memory bounded.
  // Background images combine terrain, urban land and precise water at their
  // native display resolution. Boundary images retain their thin white stroke.
  Future<void> _refreshDetailImages(
    int token,
    double zoom,
    double dpr, {
    List<_Tile>? background,
  }) {
    // A layer may wait behind another map's raster. Hide previous-scale border
    // images now, before that wait, so they cannot flash as thick stretched lines.
    if (widget.boundaryLayer != null && mounted && token == revision) {
      final (_, _, _, wanted) = _rasterGrid(zoom, dpr);
      setState(() {
        tiles = [
          for (final (key, rect) in wanted)
            if (_detailImages[key] case final image?)
              _Tile(image, rect, rect, widget.boundaryLayer!),
        ];
        loading = tiles.length != wanted.length;
      });
    }
    return _serialRaster(
      () => _renderDetailImages(token, zoom, dpr, background: background),
    );
  }

  Future<void> _renderDetailImages(
    int token,
    double zoom,
    double dpr, {
    List<_Tile>? background,
  }) async {
    if (!mounted || token != revision) return;
    if (background == null) cache.pin(this, {});
    final (exponent, renderZoom, density, wanted) = _rasterGrid(zoom, dpr);
    final imageLimit = widget.boundaryLayer == null ? 12 : 24;
    final keep = wanted.map((cell) => cell.$1).toSet();
    // Retain up to one adjacent scale if space permits. Images from other
    // prefectures/scopes are cleared by didUpdateWidget or dispose.
    final retired = <ui.Image>[];
    for (final key in _detailImages.keys.toList()) {
      if (!keep.contains(key) &&
          ((int.parse(key.split('@').first) - exponent).abs() > 1 ||
              _detailImages.length > imageLimit - wanted.length)) {
        retired.add(_detailImages.remove(key)!);
      }
    }
    void publish() {
      if (!mounted || token != revision) return;
      setState(() {
        tiles = [
          for (final (key, rect) in wanted)
            if (_detailImages[key] case final image?)
              _Tile(
                image,
                rect,
                rect,
                background != null ? 'background' : widget.boundaryLayer!,
              ),
        ];
        loading = tiles.length != wanted.length;
      });
    }

    // Hide the enlarged offline/previous-scale image synchronously. A cold
    // scale must never flash a thick border while its sharp image is prepared.
    publish();
    await _disposeImages(retired);
    if (!mounted || token != revision) return;
    final outlines = [
      for (final path in widget.boundaryPaths ?? const <Path>[])
        (path, path.getBounds()),
    ];
    final mesh =
        background == null && widget.boundaryPaths == null
            ? await (_mesh ??= PrefectureBorderMesh.load(widget.project))
            : null;
    final water =
        background != null
            ? await (_waterMesh ??= WaterMesh.load(
              widget.nationalOverview
                  ? 'national'
                  : widget.prefectureId ?? '29',
              widget.project,
            ))
            : null;
    for (final (key, rect) in wanted) {
      if (!mounted || token != revision) return;
      if (_detailImages.containsKey(key)) continue;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(density);
      canvas.translate(-rect.left, -rect.top);
      final combined = mesh?.path(rect, density) ?? Path();
      for (final (path, bounds) in outlines) {
        if (bounds.overlaps(rect.inflate(2 / density))) {
          combined.addPath(path, Offset.zero);
        }
      }
      if (background != null) {
        // One high-resolution background image contains terrain, urban land
        // and precise water. Nothing paints a separate water layer in the UI.
        canvas.save();
        canvas.translate(rect.left, rect.top);
        _GeographyPainter(
          background,
          widget.clip,
          rect.topLeft,
        ).paint(canvas, rect.size);
        canvas.restore();
        water!.paint(canvas, rect, density);
      } else {
        canvas.drawPath(
          combined,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 0.65 / renderZoom,
        );
      }
      final picture = recorder.endRecording();
      late final ui.Image image;
      try {
        image = await picture.toImage(512, 512);
      } finally {
        picture.dispose();
        combined.reset();
      }
      if (!mounted || token != revision) {
        image.dispose();
        return;
      }
      _detailImages[key] = image;
      publish();
    }
  }

  @override
  void dispose() {
    revision++;
    timer?.cancel();
    widget.transform.removeListener(_schedule);
    cache.release(this);
    _clearDetailImages();
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
                            _waterMesh = null;
                            _mesh = null;
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
      'background',
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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game.dart';
import 'relief.dart';
import 'water.dart';
import 'urban.dart';
import 'mountains.dart';
import 'map_outline.dart';
import 'map_label.dart';

class TerritoryMap extends StatefulWidget {
  const TerritoryMap({
    super.key,
    required this.atlas,
    required this.game,
    required this.selected,
    required this.cityId,
    required this.focusVersion,
    required this.onSelected,
    required this.onCitySelected,
    this.controls = const [],
    this.centerVersion = 0,
  });
  final List<Widget> controls;
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
  final int focusVersion, centerVersion;
  final ValueChanged<String> onSelected, onCitySelected;
  @override
  State<TerritoryMap> createState() => _TerritoryMapState();
}

class _TerritoryMapState extends State<TerritoryMap> {
  final controller = TransformationController();
  late Map<String, Path> paths;
  late Map<String, Path> townOutlines;
  late Map<String, Rect> bounds;
  late Map<String, Path> cityPaths;
  late Map<String, Path> cityOutlines;
  late Map<String, Rect> cityBounds;
  Size? viewport;
  MountainLayer? mountains;
  bool mountainsFailed = false;

  Future<void> _loadMountains() async {
    try {
      final loaded = await MountainLayer.load(project);
      if (mounted) setState(() => mountains = loaded);
    } catch (_) {
      if (mounted) setState(() => mountainsFailed = true);
    }
  }

  WaterLayer? water;
  bool showGeography = true;
  bool waterFailed = false;

  Future<void> _loadWater() async {
    try {
      final loaded = await WaterLayer.load(project);
      if (mounted) setState(() => water = loaded);
    } catch (_) {
      if (mounted) setState(() => waterFailed = true);
    }
  }

  UrbanLayer? urban;
  bool urbanFailed = false;

  Future<void> _loadUrban() async {
    try {
      final loaded = await UrbanLayer.load(project);
      if (mounted) setState(() => urban = loaded);
    } catch (_) {
      if (mounted) setState(() => urbanFailed = true);
    }
  }

  Relief? relief;
  bool reliefFailed = false;
  late Offset Function(math.Point<double>) project;
  late Path prefecturePath;

  Future<void> _loadRelief() async {
    try {
      final loaded = await Relief.load();
      if (!mounted) {
        loaded.image.dispose();
        return;
      }
      setState(() => relief = loaded);
    } catch (_) {
      if (mounted) setState(() => reliefFailed = true);
    }
  }

  Rect? get reliefBounds {
    final data = relief;
    if (data == null) return null;
    return Rect.fromPoints(
      project(math.Point(data.west, data.north)),
      project(math.Point(data.east, data.south)),
    );
  }

  static const mapSize = Size(1100, 1500);
  @override
  void initState() {
    super.initState();
    _buildPaths();
    _buildCities();
    _loadRelief();
    _loadWater();
    _loadUrban();
    _loadMountains();
  }

  @override
  void dispose() {
    controller.dispose();
    relief?.image.dispose();
    super.dispose();
  }

  void _buildPaths() {
    final points =
        widget.atlas.towns.values
            .expand((t) => t.polygons)
            .expand((p) => p)
            .expand((r) => r)
            .toList();
    final minX = points.map((p) => p.x).reduce(math.min),
        maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min),
        maxY = points.map((p) => p.y).reduce(math.max);
    final scale = math.min(
      (mapSize.width - 80) / ((maxX - minX) * 0.826),
      (mapSize.height - 80) / (maxY - minY),
    );
    final dx = (mapSize.width - (maxX - minX) * 0.826 * scale) / 2,
        dy = (mapSize.height - (maxY - minY) * scale) / 2;
    project =
        (p) => Offset(
          dx + (p.x - minX) * 0.826 * scale,
          dy + (maxY - p.y) * scale,
        );
    paths = {};
    townOutlines = {};
    bounds = {};
    for (final t in widget.atlas.towns.values) {
      final parts = <Path>[];
      for (final polygon in t.polygons) {
        final part = Path()..fillType = PathFillType.evenOdd;
        for (final ring in polygon) {
          if (ring.isEmpty) continue;
          final start = project(ring.first);
          part.moveTo(start.dx, start.dy);
          for (final p in ring.skip(1)) {
            final o = project(p);
            part.lineTo(o.dx, o.dy);
          }
          part.close();
        }
        parts.add(part);
      }
      final path = _union(parts);
      paths[t.id] = path;
      townOutlines[t.id] = exteriorOutline(path);
      bounds[t.id] = path.getBounds();
    }
  }

  void _buildCities() {
    cityPaths = {};
    cityOutlines = {};
    cityBounds = {};
    for (final city in widget.atlas.byCity.entries) {
      final outline = _union(city.value.map((t) => paths[t.id]!).toList());
      cityPaths[city.key] = outline;
      cityOutlines[city.key] = exteriorOutline(outline);
      cityBounds[city.key] = outline.getBounds();
    }
    prefecturePath = _union(cityPaths.values.toList());
  }

  Path _union(List<Path> parts) {
    if (parts.length == 1) return parts.single;
    final mid = parts.length ~/ 2;
    return Path.combine(
      PathOperation.union,
      _union(parts.sublist(0, mid)),
      _union(parts.sublist(mid)),
    );
  }

  @override
  void didUpdateWidget(TerritoryMap old) {
    super.didUpdateWidget(old);
    if (old.centerVersion != widget.centerVersion &&
        old.cityId != null &&
        widget.cityId != null) {
      _centerSelected();
    } else if (old.cityId != widget.cityId ||
        old.focusVersion != widget.focusVersion) {
      _fit();
    }
  }

  void _centerSelected() {
    final size = viewport;
    final target = bounds[widget.selected];
    if (size == null || target == null) return;
    final scale = controller.value.getMaxScaleOnAxis();
    controller.value = Matrix4.copy(controller.value)..setTranslationRaw(
      size.width / 2 - target.center.dx * scale,
      size.height / 2 - target.center.dy * scale,
      0,
    );
  }

  void _fit() {
    final size = viewport;
    if (size == null) return;
    final towns =
        widget.cityId == null
            ? widget.atlas.towns.values
            : widget.atlas.byCity[widget.cityId]!;
    var box = towns
        .map((t) => bounds[t.id]!)
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(15);
    if (widget.selected != null &&
        widget.cityId != null &&
        widget.focusVersion > 0) {
      final target = bounds[widget.selected]!;
      box = target.inflate(math.max(target.width, target.height) * 2 + 3);
    }
    final scale =
        math.min(size.width / box.width, size.height / box.height) * 0.9;
    controller.value =
        Matrix4.identity()
          ..translate(
            size.width / 2 - box.center.dx * scale,
            size.height / 2 - box.center.dy * scale,
          )
          ..scale(scale);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (viewport != size) {
        viewport = size;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: controller,
              constrained: false,
              minScale: 0.08,
              maxScale: 150,
              boundaryMargin: const EdgeInsets.all(2000),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final point = details.localPosition;
                  final hits =
                      (widget.cityId == null ? cityBounds : bounds).entries
                          .where(
                            (e) =>
                                (widget.cityId == null ||
                                    widget.atlas.towns[e.key]!.cityId ==
                                        widget.cityId) &&
                                e.value.contains(point) &&
                                (widget.cityId == null ? cityPaths : paths)[e
                                        .key]!
                                    .contains(point),
                          )
                          .toList()
                        ..sort(
                          (a, b) => (a.value.width * a.value.height).compareTo(
                            b.value.width * b.value.height,
                          ),
                        );
                  if (hits.isNotEmpty) {
                    if (widget.cityId == null) {
                      widget.onCitySelected(hits.first.key);
                    } else {
                      widget.onSelected(hits.first.key);
                    }
                  }
                },
                child: SizedBox(
                  width: mapSize.width,
                  height: mapSize.height,
                  child: CustomPaint(
                    painter: _MapPainter(
                      widget.cityId == null ? cityPaths : paths,
                      widget.cityId == null ? cityOutlines : townOutlines,
                      widget.cityId == null ? cityBounds : bounds,
                      widget.atlas,
                      widget.game,
                      widget.selected,
                      controller,
                      widget.cityId,
                      showGeography ? relief : null,
                      showGeography ? water : null,
                      showGeography ? urban : null,
                      showGeography ? mountains : null,
                      reliefBounds,
                      widget.cityId == null
                          ? prefecturePath
                          : cityPaths[widget.cityId]!,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showGeography)
            Positioned(
              left: 8,
              right: 68,
              bottom: 6,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reliefFailed || relief == null)
                      Text(
                        reliefFailed ? '起伏を読み込めませんでした' : '起伏を読み込み中…',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                        ),
                      ),
                    if (mountainsFailed || mountains == null)
                      Text(
                        mountainsFailed ? '山名を読み込めませんでした' : '山名を読み込み中…',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    const Text(
                      '■ 市街地（建物用地）',
                      style: TextStyle(
                        fontSize: 10,
                        color: UrbanLayer.legendColor,
                      ),
                    ),
                    if (urbanFailed || urban == null)
                      Text(
                        urbanFailed ? '市街地を読み込めませんでした' : '市街地を読み込み中…',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    if (waterFailed || water == null)
                      Text(
                        waterFailed ? '川・湖を読み込めませんでした' : '川・湖を読み込み中…',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            bottom: 8,
            child: SizedBox(
              width: 48,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 48,
                  child: IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF102A32),
                        disabledBackgroundColor: Colors.white54,
                        disabledForegroundColor: Colors.black38,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.navigation_outlined,
                          size: 22,
                          color: Colors.white,
                        ),
                        const Text(
                          'N',
                          style: TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        ...widget.controls.expand(
                          (control) => [control, const SizedBox(height: 6)],
                        ),
                        IconButton.filledTonal(
                          tooltip:
                              showGeography
                                  ? '起伏・市街地・山名・川・池・湖を非表示'
                                  : '起伏・市街地・山名・川・池・湖を表示',
                          isSelected: showGeography,
                          onPressed: () {
                            setState(() => showGeography = !showGeography);
                            // Retry failed layers when the shared overlay is enabled.
                            if (showGeography && reliefFailed) {
                              setState(() => reliefFailed = false);
                              _loadRelief();
                            }
                            if (showGeography && mountainsFailed) {
                              setState(() => mountainsFailed = false);
                              _loadMountains();
                            }
                            if (showGeography && urbanFailed) {
                              setState(() => urbanFailed = false);
                              _loadUrban();
                            }
                            if (showGeography && waterFailed) {
                              setState(() => waterFailed = false);
                              _loadWater();
                            }
                          },
                          icon: const Icon(Icons.terrain_outlined),
                          selectedIcon: const Icon(Icons.terrain),
                        ),
                        const SizedBox(height: 6),
                        IconButton.filledTonal(
                          tooltip: '拡大',
                          onPressed: () => _zoom(1.7),
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 6),
                        IconButton.filledTonal(
                          tooltip: '縮小',
                          onPressed: () => _zoom(1 / 1.7),
                          icon: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  void _zoom(double factor) {
    final size = viewport!;
    final old = controller.value;
    final scale = old.getMaxScaleOnAxis();
    final desired = (scale * factor).clamp(0.08, 150.0);
    factor = desired / scale;
    controller.value =
        Matrix4.identity()
          ..translate(size.width / 2, size.height / 2)
          ..scale(factor)
          ..translate(-size.width / 2, -size.height / 2)
          ..multiply(old);
  }
}

/// Advance the town fill only when another 10% of its population is reached.
Color townFillColor(Town town, Game game, {required bool reachable}) {
  const conquered = Color(0xFF7AE1BB);
  if (game.owned.contains(town.id)) return conquered;
  final base = reachable ? const Color(0xFFEEC47C) : const Color(0xFF43616A);
  final taps = game.progress[town.id] ?? 0;
  final step = (taps * 10 ~/ math.max(1, town.population)).clamp(0, 10);
  return Color.lerp(base, conquered, step / 10)!;
}

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.paths,
    this.outlines,
    this.bounds,
    this.atlas,
    this.game,
    this.selected,
    this.transform,
    this.cityId,
    this.relief,
    this.water,
    this.urban,
    this.mountains,
    this.reliefBounds,
    this.reliefClip,
  ) : super(repaint: transform);
  final TransformationController transform;
  final Map<String, Path> paths;
  final Map<String, Path> outlines;
  final Map<String, Rect> bounds;
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
  final Relief? relief;
  final WaterLayer? water;
  final UrbanLayer? urban;
  final MountainLayer? mountains;
  final Rect? reliefBounds;
  final Path reliefClip;
  @override
  void paint(Canvas canvas, Size size) {
    final zoom = transform.value.getMaxScaleOnAxis();
    final overview = cityId == null;
    final adjacent = <String>{};
    for (final id in game.owned) {
      adjacent.addAll(atlas.towns[id]!.neighbors);
    }
    adjacent.removeAll(game.owned);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 0.5 / zoom;
    for (final e in paths.entries) {
      if (!overview && atlas.towns[e.key]!.cityId != cityId) continue;
      final ids = overview ? atlas.byCity[e.key]!.map((t) => t.id) : [e.key];
      final owned =
          overview
              ? ids.every(game.owned.contains)
              : game.owned.contains(e.key);
      final reachable = ids.any(adjacent.contains);
      canvas.drawPath(
        e.value,
        Paint()
          ..color =
              !overview
                  ? townFillColor(
                    atlas.towns[e.key]!,
                    game,
                    reachable: reachable,
                  )
                  : owned
                  ? const Color(0xFF7AE1BB)
                  : reachable
                  ? const Color(0xFFEEC47C)
                  : const Color(0xFF43616A),
      );
    }
    final terrain = relief;
    final terrainRect = reliefBounds;
    if (terrain != null && terrainRect != null) {
      canvas.save();
      canvas.clipPath(reliefClip);
      canvas.drawImageRect(
        terrain.image,
        Rect.fromLTWH(
          0,
          0,
          terrain.image.width.toDouble(),
          terrain.image.height.toDouble(),
        ),
        terrainRect,
        Paint()
          ..blendMode = BlendMode.modulate
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
    urban?.paint(canvas, reliefClip);
    water?.paint(canvas, reliefClip);
    final occupiedLabels = <Rect>[];
    // Borders, labels and selection remain above the terrain and water.
    for (final e in paths.entries) {
      if (!overview && atlas.towns[e.key]!.cityId != cityId) continue;
      canvas.drawPath(outlines[e.key]!, stroke);
      if (!overview && e.key == selected) {
        canvas.drawPath(
          e.value,
          Paint()..color = Colors.white.withValues(alpha: 0.2),
        );
      }
      final box = bounds[e.key]!;
      final label = TextPainter(
        text: TextSpan(
          text: overview ? atlas.cities[e.key] : atlas.towns[e.key]!.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            fontSize: 12 / zoom,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (overview ||
          e.key == selected ||
          (label.width < box.width && label.height < box.height)) {
        occupiedLabels.add(
          Rect.fromCenter(
            center: box.center,
            width: label.width + 4 / zoom,
            height: label.height + 4 / zoom,
          ),
        );
        paintMapLabel(
          canvas,
          label,
          box.center - Offset(label.width / 2, label.height / 2),
          zoom,
        );
      }
    }
    water?.paintLabels(
      canvas,
      reliefClip,
      zoom,
      occupiedLabels,
      municipal: !overview,
    );
    mountains?.paintLabels(canvas, reliefClip, zoom, occupiedLabels);
    if (game.home != null) {
      final town = atlas.towns[game.home]!;
      if (overview || town.cityId == cityId) {
        final p = bounds[overview ? town.cityId : town.id]!.center;
        canvas.drawCircle(
          p,
          4 / zoom,
          Paint()..color = const Color(0xFF101C2B),
        );
        canvas.drawCircle(p, 2 / zoom, Paint()..color = Colors.white);
      }
    }
    // Keep both the selection and active campaign above all other map layers.
    final highlighted = <String>{};
    for (final id in [selected, game.attackTarget]) {
      final town = atlas.towns[id];
      if (town == null) continue;
      if (overview) {
        highlighted.add(town.cityId);
      } else if (town.cityId == cityId) {
        highlighted.add(town.id);
      }
    }
    for (final id in highlighted) {
      final path = outlines[id];
      if (path == null) continue;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom
          ..color = const Color(0xFFFF3B30),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'game.dart';
import 'map_view.dart';
import 'geography_tiles.dart';
import 'water.dart';
import 'mountains.dart';
import 'map_outline.dart';
import 'map_label.dart';
import 'office_symbols.dart';
import 'map_compass.dart';
import 'border_tiles.dart';
import 'map_paint_snapshot.dart';
import 'map_controls.dart';

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
    this.prefectureId = '29',
    this.controls = const [],
    this.secondaryControls = const [],
    this.centerVersion = 0,
    this.fitScale = 0.9,
    this.controlsBottomInset = 8,
    this.showControls = true,
    this.initialView,
    this.onViewChanged,
  });
  final String prefectureId;
  final List<Widget> controls, secondaryControls;
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
  final int focusVersion, centerVersion;
  final double fitScale, controlsBottomInset;
  final bool showControls;
  final MapViewState? initialView;
  final ValueChanged<MapViewState>? onViewChanged;
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
  bool _initialized = false;
  MapViewState? _pendingRestore;
  late Map<String, Offset> officePoints;
  MountainLayer? mountains;
  bool mountainsFailed = false;

  Future<void> _loadMountains() async {
    try {
      final loaded = await MountainLayer.load(
        project,
        prefectureId: widget.prefectureId,
      );
      if (mounted) setState(() => mountains = loaded);
    } catch (_) {
      if (mounted) setState(() => mountainsFailed = true);
    }
  }

  WaterLayer? water;
  bool showGeography = true;
  final _busyImageLayers = <String>{'background', 'border'};
  bool get _imagesBusy => _busyImageLayers.isNotEmpty;

  void _imageBusy(String layer, bool busy) {
    if (busy) {
      _busyImageLayers.add(layer);
    } else {
      _busyImageLayers.remove(layer);
    }
    // Child layers can notify during build. Record the lock immediately and
    // update the button/gesture appearance after the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    // A completion can arrive while no frame is scheduled. Ensure the deferred
    // button update runs even after all map animations have stopped.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool waterFailed = false;

  Future<void> _loadWater() async {
    try {
      final loaded = await WaterLayer.loadLabels(
        project,
        prefectureId: widget.prefectureId,
      );
      if (mounted) setState(() => water = loaded);
    } catch (_) {
      if (mounted) setState(() => waterFailed = true);
    }
  }

  late Offset Function(math.Point<double>) project;
  late Path prefecturePath;

  static const mapSize = Size(1100, 1500);
  @override
  void initState() {
    super.initState();
    _pendingRestore = widget.initialView;
    showGeography = widget.initialView?.showGeography ?? true;
    controller.addListener(_publishView);
    _buildPaths();
    _buildCities();
    officePoints = {
      for (final o in widget.atlas.mapOffices.values.where(
        (o) => o.cityId.startsWith(widget.prefectureId),
      ))
        o.id: project(o.point),
    };
    _loadWater();
    _loadMountains();
  }

  @override
  void dispose() {
    controller.removeListener(_publishView);
    controller.dispose();
    // Release native path storage eagerly when leaving a detailed map.
    for (final path in {
      ...paths.values,
      ...townOutlines.values,
      ...cityPaths.values,
      ...cityOutlines.values,
      prefecturePath,
    }) {
      path.reset();
    }
    super.dispose();
  }

  void _buildPaths() {
    final points =
        widget.atlas.towns.values
            .where((t) => t.cityId.startsWith(widget.prefectureId))
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
    for (final t in widget.atlas.towns.values.where(
      (t) => t.cityId.startsWith(widget.prefectureId),
    )) {
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
      final detailed = widget.prefectureId == '29' || t.cityId == widget.cityId;
      final path =
          detailed ? _union(parts) : (Path()..fillType = PathFillType.evenOdd);
      if (!detailed) {
        for (final part in parts) {
          path.addPath(part, Offset.zero);
        }
      }
      paths[t.id] = path;
      townOutlines[t.id] = detailed ? exteriorOutline(path) : Path();
      bounds[t.id] = path.getBounds();
    }
    if (widget.cityId != null) detailedCities.add(widget.cityId!);
  }

  final Set<String> detailedCities = {};
  void _detailCity(String? city) {
    if (widget.prefectureId == '29' ||
        city == null ||
        !detailedCities.add(city)) {
      return;
    }
    for (final town in widget.atlas.byCity[city]!) {
      final path = _union([
        for (final polygon in town.polygons) _polygonPath([polygon]),
      ]);
      paths[town.id] = path;
      townOutlines[town.id] = exteriorOutline(path);
      bounds[town.id] = path.getBounds();
    }
  }

  void _buildCities() {
    cityPaths = {};
    cityOutlines = {};
    cityBounds = {};
    for (final city in widget.atlas.byCity.entries.where(
      (e) => e.key.startsWith(widget.prefectureId),
    )) {
      final prebuilt = widget.atlas.cityPolygons[city.key];
      final outline =
          prebuilt == null
              ? _union(city.value.map((t) => paths[t.id]!).toList())
              : _polygonPath(prebuilt);
      cityPaths[city.key] = outline;
      cityOutlines[city.key] = exteriorOutline(outline);
      cityBounds[city.key] = outline.getBounds();
    }
    final prebuilt = widget.atlas.prefecturePolygons[widget.prefectureId];
    prefecturePath =
        prebuilt == null
            ? _union(cityPaths.values.toList())
            : _polygonPath(prebuilt);
  }

  Path _polygonPath(List<List<List<math.Point<double>>>> polygons) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in polygons) {
      for (final ring in polygon) {
        if (ring.isEmpty) continue;
        final first = project(ring.first);
        path.moveTo(first.dx, first.dy);
        for (final point in ring.skip(1)) {
          final p = project(point);
          path.lineTo(p.dx, p.dy);
        }
        path.close();
      }
    }
    return path;
  }

  Path _union(List<Path> parts) {
    if (parts.isEmpty) return Path();
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
    _detailCity(widget.cityId);
    if (old.game != widget.game) {
      showGeography = true;
      _pendingRestore = null;
      _fit();
    } else if (old.centerVersion != widget.centerVersion &&
        old.cityId != null &&
        widget.cityId != null) {
      _centerSelected();
    } else if (old.cityId != widget.cityId ||
        old.focusVersion != widget.focusVersion) {
      _fit();
    } else if (old.selected != widget.selected) {
      _publishView();
    }
  }

  MapViewState? _captureView() {
    final size = viewport;
    if (!_initialized || size == null) return null;
    return MapViewState(
      center: controller.toScene(Offset(size.width / 2, size.height / 2)),
      scale: controller.value.getMaxScaleOnAxis(),
      selected: widget.selected,
      cityId: widget.cityId,
      showGeography: showGeography,
      prefectureId: widget.prefectureId,
    );
  }

  void _publishView() {
    // The visible office semantics must follow pan/zoom, not just repaint.
    if (mounted) setState(() {});
    final view = _captureView();
    if (view != null) widget.onViewChanged?.call(view);
  }

  void _applyView(MapViewState view) {
    final size = viewport!;
    _initialized = true;
    controller.value =
        Matrix4.identity()
          ..translate(
            size.width / 2 - view.center.dx * view.scale,
            size.height / 2 - view.center.dy * view.scale,
          )
          ..scale(view.scale);
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
            ? widget.atlas.towns.values.where(
              (t) => t.cityId.startsWith(widget.prefectureId),
            )
            : widget.atlas.byCity[widget.cityId]!;
    var box = towns
        .map((t) => bounds[t.id]!)
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(15);
    // Some island municipalities have their headquarters on another island.
    // Keep the actual office point visible instead of moving it onto territory.
    for (final office in widget.atlas.mapOffices.values) {
      if (!officePoints.containsKey(office.id) ||
          (widget.cityId != null && office.cityId != widget.cityId)) {
        continue;
      }
      box = box.expandToInclude(
        Rect.fromCircle(center: officePoints[office.id]!, radius: 15),
      );
    }
    if (widget.selected != null &&
        widget.cityId != null &&
        widget.focusVersion > 0) {
      final target = bounds[widget.selected]!;
      box = target.inflate(math.max(target.width, target.height) * 2 + 3);
    }
    final scale =
        math.min(size.width / box.width, size.height / box.height) *
        widget.fitScale;
    _initialized = true;
    controller.value =
        Matrix4.identity()
          ..translate(
            size.width / 2 - box.center.dx * scale,
            size.height / 2 - box.center.dy * scale,
          )
          ..scale(scale);
  }

  void _selectOffice(String officeId) {
    final office = widget.atlas.mapOffices[officeId]!;
    final city = office.cityId;
    if (widget.cityId == null) widget.onCitySelected(city);
    final town = office.townId;
    if (town != null) {
      widget.onSelected(town);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${office.name}${office.address.isEmpty ? '' : '：${office.address}'}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (viewport != size) {
        final retained = _pendingRestore ?? _captureView();
        _pendingRestore = null;
        viewport = size;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (retained != null) {
            _applyView(retained);
          } else {
            _fit();
          }
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: controller,
              constrained: false,
              scaleEnabled: !_imagesBusy,
              minScale: 0.08,
              maxScale: 150,
              boundaryMargin: const EdgeInsets.all(2000),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final point = details.localPosition;
                  final zoom = controller.value.getMaxScaleOnAxis();
                  final offices =
                      officePoints.entries
                          .where(
                            (e) =>
                                (widget.cityId == null ||
                                    widget.atlas.mapOffices[e.key]!.cityId ==
                                        widget.cityId) &&
                                (e.value - point).distance * zoom <= 14,
                          )
                          .toList()
                        ..sort(
                          (a, b) => (a.value - point).distance.compareTo(
                            (b.value - point).distance,
                          ),
                        );
                  if (offices.isNotEmpty) {
                    _selectOffice(offices.first.key);
                    return;
                  }
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          painter: _MapPainter(
                            widget.cityId == null ? cityPaths : paths,
                            widget.cityId == null ? cityOutlines : townOutlines,
                            widget.cityId == null ? cityBounds : bounds,
                            widget.atlas,
                            widget.game,
                            widget.selected,
                            controller,
                            widget.cityId,
                            officePoints,
                            _selectOffice,
                            showGeography ? water : null,
                            showGeography ? mountains : null,
                            widget.cityId == null
                                ? prefecturePath
                                : cityPaths[widget.cityId]!,
                            size,
                            paths,
                            foreground: false,
                          ),
                        ),
                      ),
                      GeographyTiles(
                        onBusyChanged: (busy) => _imageBusy('background', busy),
                        prefectureId: widget.prefectureId,
                        transform: controller,
                        project: project,
                        viewport: size,
                        clip:
                            widget.cityId == null
                                ? prefecturePath
                                : cityPaths[widget.cityId]!,
                        enabled: showGeography,
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          painter: _MapPainter(
                            widget.cityId == null ? cityPaths : paths,
                            widget.cityId == null ? cityOutlines : townOutlines,
                            widget.cityId == null ? cityBounds : bounds,
                            widget.atlas,
                            widget.game,
                            widget.selected,
                            controller,
                            widget.cityId,
                            officePoints,
                            _selectOffice,
                            showGeography ? water : null,
                            showGeography ? mountains : null,
                            widget.cityId == null
                                ? prefecturePath
                                : cityPaths[widget.cityId]!,
                            size,
                            paths,
                            colors: true,
                            colorOpacity: showGeography ? 0.55 : 1.0,
                          ),
                        ),
                      ),
                      // Boundaries top territory colors; labels and attack highlights stay in front.
                      BorderTiles(
                        onBusyChanged: (busy) => _imageBusy('border', busy),
                        boundaryPaths:
                            widget.cityId == null
                                ? cityOutlines.values
                                : widget.atlas.byCity[widget.cityId]!.map(
                                  (town) => townOutlines[town.id]!,
                                ),
                        transform: controller,
                        project: project,
                        viewport: size,
                        clip:
                            widget.cityId == null
                                ? prefecturePath
                                : cityPaths[widget.cityId]!,
                        prefectureId: widget.prefectureId,
                        layer: widget.cityId == null ? 'city' : 'town',
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          willChange: true,
                          painter: _MapPainter(
                            widget.cityId == null ? cityPaths : paths,
                            widget.cityId == null ? cityOutlines : townOutlines,
                            widget.cityId == null ? cityBounds : bounds,
                            widget.atlas,
                            widget.game,
                            widget.selected,
                            controller,
                            widget.cityId,
                            officePoints,
                            _selectOffice,
                            showGeography ? water : null,
                            showGeography ? mountains : null,
                            widget.cityId == null
                                ? prefecturePath
                                : cityPaths[widget.cityId]!,
                            size,
                            paths,
                            foreground: true,
                          ),
                        ),
                      ),
                    ],
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
                    if (mountainsFailed || mountains == null)
                      Text(
                        mountainsFailed ? '山名を読み込めませんでした' : '山名を読み込み中…',
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
          const Positioned(left: 8, top: 8, child: MapCompass()),
          if (widget.showControls)
            Positioned(
              right: 12,
              top: 4,
              bottom: widget.controlsBottomInset,
              child: SizedBox(
                width: 40,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: 40,
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
                          ...widget.controls.expand(
                            (control) => [
                              lockMapNavigationControl(
                                control,
                                () => _imagesBusy,
                              ),
                              const SizedBox(height: 2),
                            ],
                          ),
                          IconButton.filledTonal(
                            tooltip: '拡大',
                            onPressed: _imagesBusy ? null : () => _zoom(1.7),
                            icon: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 2),
                          IconButton.filledTonal(
                            tooltip: '縮小',
                            onPressed:
                                _imagesBusy ? null : () => _zoom(1 / 1.7),
                            icon: const Icon(Icons.remove),
                          ),
                          const SizedBox(height: 2),
                          ...widget.secondaryControls.expand(
                            (control) => [
                              lockMapNavigationControl(
                                control,
                                () => _imagesBusy,
                              ),
                              const SizedBox(height: 2),
                            ],
                          ),
                          IconButton.filledTonal(
                            tooltip:
                                showGeography
                                    ? '起伏・市街地・山名・川・池・湖を非表示'
                                    : '起伏・市街地・山名・川・池・湖を表示',
                            isSelected: showGeography,
                            onPressed:
                                _imagesBusy
                                    ? null
                                    : () {
                                      if (_imagesBusy) return;
                                      setState(
                                        () => showGeography = !showGeography,
                                      );
                                      // Retry failed layers when the shared overlay is enabled.
                                      _publishView();
                                      if (showGeography && mountainsFailed) {
                                        setState(() => mountainsFailed = false);
                                        _loadMountains();
                                      }
                                      if (showGeography && waterFailed) {
                                        setState(() => waterFailed = false);
                                        _loadWater();
                                      }
                                    },
                            icon: const Icon(Icons.terrain_outlined),
                            selectedIcon: const Icon(Icons.terrain),
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
    if (_imagesBusy) return;
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
    this.officePoints,
    this.onOfficeSelected,
    this.water,
    this.mountains,
    this.reliefClip,
    this.viewportSize,
    this.townPaths, {
    this.foreground = false,
    this.colors = false,
    this.colorOpacity = 1.0,
  }) : snapshot = MapPaintSnapshot(game),
       super(repaint: foreground ? transform : null);
  final MapPaintSnapshot snapshot;
  final bool foreground;
  final bool colors;
  final double colorOpacity;
  final TransformationController transform;
  final Map<String, Path> paths;
  final Map<String, Path> townPaths;
  final Map<String, Path> outlines;
  final Map<String, Rect> bounds;
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
  final Map<String, Offset> officePoints;
  final ValueChanged<String> onOfficeSelected;
  final WaterLayer? water;
  final MountainLayer? mountains;
  final Path reliefClip;
  final Size viewportSize;
  @override
  void paint(Canvas canvas, Size size) {
    final zoom = transform.value.getMaxScaleOnAxis();
    final overview = cityId == null;
    if (!foreground && !colors) {
      for (final e in paths.entries) {
        if (!overview && atlas.towns[e.key]!.cityId != cityId) continue;
        canvas.drawPath(e.value, Paint()..color = const Color(0xFF43616A));
      }
      return;
    }
    if (colors) {
      for (final entry in townPaths.entries) {
        final town = atlas.towns[entry.key]!;
        if (!overview && town.cityId != cityId) continue;
        final reachable = game.isReachable(entry.key);
        if (!game.owned.contains(entry.key) &&
            !game.progress.containsKey(entry.key) &&
            !reachable) {
          continue;
        }
        canvas.drawPath(
          entry.value,
          Paint()
            ..color = townFillColor(
              town,
              game,
              reachable: reachable,
            ).withValues(alpha: colorOpacity),
        );
      }
      return;
    }
    final occupiedLabels = <Rect>[
      for (final e in officePoints.entries)
        if (overview || e.key == cityId)
          Rect.fromCircle(center: e.value, radius: 11 / zoom),
    ];
    // Labels and selection remain above the terrain and water.
    for (final e in paths.entries) {
      if (!overview && atlas.towns[e.key]!.cityId != cityId) continue;
      // Static city/town outlines are supplied by BorderTiles.
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
        var labelCenter = box.center;
        final labelRect = Rect.fromCenter(
          center: labelCenter,
          width: label.width + 4 / zoom,
          height: label.height + 4 / zoom,
        );
        if (occupiedLabels.any((r) => r.overlaps(labelRect))) {
          labelCenter += Offset(0, 18 / zoom);
        }
        final placedLabel = Rect.fromCenter(
          center: labelCenter,
          width: label.width + 4 / zoom,
          height: label.height + 4 / zoom,
        );
        if (!e.key.startsWith('29') &&
            e.key != selected &&
            occupiedLabels.any((r) => r.overlaps(placedLabel))) {
          label.dispose();
          continue;
        }
        occupiedLabels.add(placedLabel);
        paintMapLabel(
          canvas,
          label,
          labelCenter - Offset(label.width / 2, label.height / 2),
          zoom,
        );
      }
      label.dispose();
    }
    water?.paintLabels(
      canvas,
      reliefClip,
      zoom,
      occupiedLabels,
      municipal: !overview,
      viewport: Rect.fromPoints(
        transform.toScene(Offset.zero),
        transform.toScene(viewportSize.bottomRight(Offset.zero)),
      ),
    );
    mountains?.paintLabels(
      canvas,
      reliefClip,
      zoom,
      occupiedLabels,
      municipal: !overview,
      viewport: Rect.fromPoints(
        transform.toScene(Offset.zero),
        transform.toScene(viewportSize.bottomRight(Offset.zero)),
      ),
    );
    if (game.home != null) {
      final town = atlas.towns[game.home]!;
      if ((overview || town.cityId == cityId) &&
          bounds.containsKey(overview ? town.cityId : town.id)) {
        final p = bounds[overview ? town.cityId : town.id]!.center;
        canvas.drawCircle(
          p,
          4 / zoom,
          Paint()..color = const Color(0xFF101C2B),
        );
        canvas.drawCircle(p, 2 / zoom, Paint()..color = Colors.white);
      }
    }
    // Keep the selection and active campaign above map fills and labels.
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
    for (final office in atlas.mapOffices.values) {
      if (!officePoints.containsKey(office.id)) continue;
      if (!overview && office.cityId != cityId) continue;
      paintOfficeSymbol(
        canvas,
        officePoints[office.id]!,
        zoom,
        isCity: office.isCity,
        ready: office.townId != null && game.canStartQuizAt(office.townId!),
        mastered: game.mastered.contains(office.cityId),
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    if (!foreground) return [];
    final zoom = transform.value.getMaxScaleOnAxis();
    final visible = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(Offset(viewportSize.width, viewportSize.height)),
    );
    final nodes = <CustomPainterSemantics>[];
    for (final office in atlas.mapOffices.values) {
      if (!officePoints.containsKey(office.id)) continue;
      if (cityId != null && office.cityId != cityId) continue;
      final rect = Rect.fromCircle(
        center: officePoints[office.id]!,
        radius: 14 / zoom,
      ).intersect(visible);
      if (rect.isEmpty) continue;
      nodes.add(
        CustomPainterSemantics(
          key: ValueKey('office-${office.id}'),
          rect: rect,
          properties: SemanticsProperties(
            label:
                '${office.name}${office.townId == null ? '' : '（${atlas.towns[office.townId]!.name}）'}',
            button: true,
            onTap: () => onOfficeSelected(office.id),
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };

  @override
  bool shouldRebuildSemantics(covariant _MapPainter oldDelegate) => true;

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      foreground != old.foreground ||
      colors != old.colors ||
      colorOpacity != old.colorOpacity ||
      paths != old.paths ||
      cityId != old.cityId ||
      atlas != old.atlas ||
      (foreground
          ? selected != old.selected ||
              water != old.water ||
              mountains != old.mountains ||
              viewportSize != old.viewportSize ||
              reliefClip != old.reliefClip ||
              !snapshot.sameForeground(old.snapshot)
          : !snapshot.sameColors(old.snapshot));
}

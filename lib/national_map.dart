import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'game.dart';
import 'national_atlas.dart';
import 'territory_map.dart';
import 'map_view.dart';
import 'geography_tiles.dart';
import 'map_compass.dart';
import 'border_tiles.dart';
import 'map_paint_snapshot.dart';
import 'map_controls.dart';
import 'raster_geometry.dart';
import 'national_territory.dart';

class NationalMap extends StatefulWidget {
  const NationalMap({
    super.key,
    required this.data,
    required this.game,
    required this.onPrefectureSelected,
    this.controls = const [],
    this.initialView,
    this.onViewChanged,
    this.prefectureId = '29',
    this.controlsBottomInset = 8,
  });
  final NationalAtlas data;
  final Game game;
  final ValueChanged<String> onPrefectureSelected;
  final List<Widget> controls;
  final MapViewState? initialView;
  final ValueChanged<MapViewState>? onViewChanged;
  final String prefectureId;
  final double controlsBottomInset;
  @override
  State<NationalMap> createState() => _NationalMapState();
}

class _NationalMapState extends State<NationalMap> {
  // Include Minamitorishima and Okinotorishima in Tokyo's offshore territory.
  static const sceneSize = Size(1440, 1360);
  final boundaryClip = Path()..addRect(Offset.zero & sceneSize);
  final transform = TransformationController();
  final paths = <String, Path>{};
  final labelBounds = <String, Rect>{};
  bool initialized = false;
  bool showGeography = true;
  final _busyImageLayers = <String>{'background', 'border'};
  bool _territoryLoading = true;
  bool get _imagesBusy => _territoryLoading || _busyImageLayers.isNotEmpty;

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

  final territoryPaths = <String, Path>{};
  String? error;
  Size? viewport;
  late final Offset Function(math.Point<double>) project;

  @override
  void initState() {
    super.initState();
    // A common projection retains Hokkaido and the southern islands in one scene.
    project = (p) => Offset(40 + (p.x - 122) * 42, 40 + (46 - p.y) * 50);
    for (final p in widget.data.prefectures.values) {
      paths[p.id] = _path(p.polygons);
      // Offshore islands must not pull the Tokyo label into the Pacific.
      labelBounds[p.id] = p.polygons
          .map((part) => rasterPolygonBounds(part, project))
          .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
    }
    showGeography = widget.initialView?.showGeography ?? true;
    _loadTerritory();
  }

  Path _path(List<List<List<math.Point<double>>>> polygons) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in polygons) {
      for (final ring in polygon) {
        if (ring.isEmpty) continue;
        final first = project(ring.first);
        path.moveTo(first.dx, first.dy);
        for (final p in ring.skip(1)) {
          final point = project(p);
          path.lineTo(point.dx, point.dy);
        }
        path.close();
      }
    }
    return path;
  }

  Future<void> _loadTerritory() async {
    final converted = <String, Path>{};
    var published = false;
    _territoryLoading = true;
    try {
      final ids = {...widget.game.owned, ...widget.game.progress.keys};
      for (final id in widget.game.owned) {
        ids.addAll(widget.data.atlas.towns[id]!.neighbors);
        ids.addAll(widget.data.atlas.seaNeighbors[id] ?? const <String>{});
      }
      await widget.data.releaseGeometry();
      for (final pref in ids.map((id) => id.substring(0, 2)).toSet()) {
        if (!mounted) return;
        final loaded = await loadNationalTerritory(
          prefecture: pref,
          towns: ids.where((id) => id.startsWith(pref)).toSet(),
          sourceToTown: widget.data.atlas.sourceToTown,
          project: project,
          isCurrent: () => mounted,
        );
        if (!mounted) {
          for (final path in loaded.values) {
            path.reset();
          }
          return;
        }
        converted.addAll(loaded);
      }
      if (!mounted) return;
      for (final path in territoryPaths.values) {
        path.reset();
      }
      territoryPaths
        ..clear()
        ..addAll(converted);
      published = true;
      error = null;
    } catch (_) {
      error = '領土の形状を読み込めませんでした';
    } finally {
      if (!published) {
        for (final path in converted.values) {
          path.reset();
        }
      }
      if (mounted) setState(() => _territoryLoading = false);
    }
  }

  void _publishView() {
    final size = viewport;
    if (size == null) return;
    widget.onViewChanged?.call(
      MapViewState(
        center: transform.toScene(size.center(Offset.zero)),
        scale: transform.value.getMaxScaleOnAxis(),
        selected: null,
        cityId: null,
        prefectureId: widget.prefectureId,
        nationalView: true,
        showGeography: showGeography,
      ),
    );
  }

  void _zoom(double factor) {
    if (_imagesBusy && factor != 1) return;
    final size = viewport!;
    final center = transform.toScene(size.center(Offset.zero));
    final scale = MapImageScale.snap(
      transform.value.getMaxScaleOnAxis() * factor,
      50,
      5,
    );
    transform.value =
        Matrix4.identity()
          ..translate(
            size.width / 2 - center.dx * scale,
            size.height / 2 - center.dy * scale,
          )
          ..scale(scale);
  }

  @override
  void dispose() {
    transform.dispose();
    for (final path in {...paths.values, ...territoryPaths.values}) {
      path.reset();
    }
    boundaryClip.reset();
    territoryPaths.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '全国地図',
    container: true,
    explicitChildNodes: true,
    child: LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        if (!initialized) {
          initialized = true;
          final saved = widget.initialView;
          final scale = MapImageScale.snap(
            saved?.scale ??
                math.min(
                  c.maxWidth / sceneSize.width,
                  c.maxHeight / sceneSize.height,
                ),
            50,
            5,
            fit: saved == null,
          );
          final center = saved?.center ?? sceneSize.center(Offset.zero);
          transform.value =
              Matrix4.identity()
                ..translate(
                  c.maxWidth / 2 - center.dx * scale,
                  c.maxHeight / 2 - center.dy * scale,
                )
                ..scale(scale);
          transform.addListener(_publishView);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _publishView();
          });
        } else if (viewport != size) {
          final center = transform.toScene(viewport!.center(Offset.zero));
          final scale = transform.value.getMaxScaleOnAxis();
          viewport = size;
          transform.value =
              Matrix4.identity()
                ..translate(
                  size.width / 2 - center.dx * scale,
                  size.height / 2 - center.dy * scale,
                )
                ..scale(scale);
        }
        viewport = size;
        final adjacent = <String>{};
        for (final id in widget.game.owned) {
          adjacent.addAll(widget.data.atlas.towns[id]!.neighbors);
          adjacent.addAll(
            widget.data.atlas.seaNeighbors[id] ?? const <String>{},
          );
        }
        final territory = territoryPaths;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: transform,
                scaleEnabled: !_imagesBusy,
                minScale: MapImageScale.scale(MapImageScale.minLevel, 50),
                maxScale: MapImageScale.scale(5, 50),
                onInteractionEnd: (_) => _zoom(1),
                constrained: false,
                boundaryMargin: const EdgeInsets.all(2000),
                child: GestureDetector(
                  onTapUp: (details) {
                    if (_imagesBusy) return;
                    final hit = paths.entries.where(
                      (e) => e.value.contains(details.localPosition),
                    );
                    if (hit.isNotEmpty) {
                      widget.onPrefectureSelected(hit.first.key);
                    }
                  },
                  child: SizedBox(
                    width: sceneSize.width,
                    height: sceneSize.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            isComplex: true,
                            painter: _NationalPainter(
                              paths,
                              labelBounds,
                              territory,
                              widget.data,
                              widget.game,
                              adjacent,
                              transform,
                              widget.onPrefectureSelected,
                              foreground: false,
                            ),
                          ),
                        ),
                        GeographyTiles(
                          onBusyChanged:
                              (busy) => _imageBusy('background', busy),
                          nationalOverview: true,
                          transform: transform,
                          project: project,
                          viewport: size,
                          // The prepared image already excludes the sea.
                          clip: boundaryClip,
                          enabled: showGeography,
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            isComplex: true,
                            painter: _NationalPainter(
                              paths,
                              labelBounds,
                              territory,
                              widget.data,
                              widget.game,
                              adjacent,
                              transform,
                              widget.onPrefectureSelected,
                              colors: true,
                              colorOpacity: showGeography ? 0.55 : 1.0,
                            ),
                          ),
                        ),
                        // Boundaries top territory colors; labels and attack highlights stay in front.
                        BorderTiles(
                          onBusyChanged: (busy) => _imageBusy('border', busy),
                          transform: transform,
                          project: project,
                          viewport: size,
                          // The baked coast clips itself. Simplified per-county
                          // faces contain gaps/overlaps and must not cut this mesh.
                          clip: boundaryClip,
                          layer: 'pref',
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            willChange: true,
                            painter: _NationalPainter(
                              paths,
                              labelBounds,
                              territory,
                              widget.data,
                              widget.game,
                              adjacent,
                              transform,
                              widget.onPrefectureSelected,
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
            const Positioned(left: 8, top: 8, child: MapCompass()),
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
                            onPressed:
                                _imagesBusy ||
                                        MapImageScale.level(
                                              transform.value
                                                  .getMaxScaleOnAxis(),
                                              50,
                                            ) >=
                                            5
                                    ? null
                                    : () => _zoom(2),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton.filledTonal(
                            tooltip: '縮小',
                            onPressed:
                                _imagesBusy ||
                                        MapImageScale.level(
                                              transform.value
                                                  .getMaxScaleOnAxis(),
                                              50,
                                            ) <=
                                            MapImageScale.minLevel
                                    ? null
                                    : () => _zoom(0.5),
                            icon: const Icon(Icons.remove),
                          ),
                          const SizedBox(height: 2),
                          IconButton.filledTonal(
                            tooltip:
                                showGeography
                                    ? '起伏・市街地・川・池・湖を非表示'
                                    : '起伏・市街地・川・池・湖を表示',
                            isSelected: showGeography,
                            onPressed:
                                _imagesBusy
                                    ? null
                                    : () {
                                      if (_imagesBusy) return;
                                      setState(
                                        () => showGeography = !showGeography,
                                      );
                                      _publishView();
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
            if (error != null)
              Positioned(
                left: 8,
                top: 35,
                child: TextButton(
                  onPressed: _territoryLoading ? null : _loadTerritory,
                  child: Text('$error · 再試行'),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _NationalPainter extends CustomPainter {
  _NationalPainter(
    this.paths,
    this.labelBounds,
    this.territory,
    this.data,
    this.game,
    this.adjacent,
    this.transform,
    this.onPrefectureSelected, {
    this.foreground = false,
    this.colors = false,
    this.colorOpacity = 1.0,
  }) : snapshot = MapPaintSnapshot(game),
       territoryCount = territory.length,
       super(repaint: foreground ? transform : null);
  final MapPaintSnapshot snapshot;
  final int territoryCount;
  final bool foreground;
  final bool colors;
  final double colorOpacity;
  final Map<String, Path> paths, territory;
  final Map<String, Rect> labelBounds;
  final NationalAtlas data;
  final Game game;
  final Set<String> adjacent;
  final TransformationController transform;
  final ValueChanged<String> onPrefectureSelected;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    if (!foreground) return [];
    final zoom = transform.value.getMaxScaleOnAxis();
    return [
      for (final entry in labelBounds.entries)
        CustomPainterSemantics(
          key: ValueKey('prefecture-${entry.key}'),
          rect: Rect.fromCenter(
            center: entry.value.center,
            width: 28 / zoom,
            height: 28 / zoom,
          ),
          properties: SemanticsProperties(
            label: data.prefectures[entry.key]!.name,
            button: true,
            onTap: () => onPrefectureSelected(entry.key),
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };
  @override
  void paint(Canvas canvas, Size size) {
    final zoom = transform.value.getMaxScaleOnAxis();
    if (!foreground && !colors) {
      for (final path in paths.values) {
        canvas.drawPath(path, Paint()..color = const Color(0xFF43616A));
      }
      return;
    }
    if (colors) {
      // Only town shapes receive ownership and progress colors; prefectures stay neutral.
      for (final e in territory.entries) {
        canvas.drawPath(
          e.value,
          Paint()
            ..color = townFillColor(
              data.atlas.towns[e.key]!,
              game,
              reachable: adjacent.contains(e.key),
            ).withValues(alpha: colorOpacity),
        );
      }
      return;
    }
    // Keep prefecture borders and labels above the geography layers.
    for (final e in paths.entries) {
      // Static prefecture outlines are supplied by BorderTiles.
      final bounds = labelBounds[e.key]!;
      final label = TextPainter(
        text: TextSpan(
          text: data.prefectures[e.key]!.name,
          style: TextStyle(
            fontFamily: 'NotoSansJP',
            color: Colors.white,
            fontSize: 11 / zoom,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (label.width < bounds.width || zoom > 1) {
        label.paint(
          canvas,
          bounds.center - Offset(label.width / 2, label.height / 2),
        );
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_NationalPainter old) =>
      foreground != old.foreground ||
      colors != old.colors ||
      colorOpacity != old.colorOpacity ||
      paths != old.paths ||
      labelBounds != old.labelBounds ||
      (colors && territoryCount != old.territoryCount) ||
      (foreground
          ? !snapshot.sameForeground(old.snapshot)
          : colors && !snapshot.sameColors(old.snapshot));
}

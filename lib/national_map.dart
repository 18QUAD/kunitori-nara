import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'game.dart';
import 'national_atlas.dart';
import 'territory_map.dart';
import 'map_view.dart';

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
  final transform = TransformationController();
  final paths = <String, Path>{};
  final labelBounds = <String, Rect>{};
  bool initialized = false;
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
          .map((part) => _path([part]).getBounds())
          .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
    }
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
    try {
      final ids = {...widget.game.owned, ...widget.game.progress.keys};
      for (final id in widget.game.owned) {
        ids.addAll(widget.data.atlas.towns[id]!.neighbors);
      }
      await Future.wait(
        ids
            .map((id) => id.substring(0, 2))
            .toSet()
            .map(widget.data.ensureGeometry),
      );
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) setState(() => error = '領土の形状を読み込めませんでした');
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
      ),
    );
  }

  void _zoom(double factor) {
    final size = viewport!;
    final center = transform.toScene(size.center(Offset.zero));
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      0.08,
      150.0,
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
          final scale =
              saved?.scale ??
              math
                  .min(
                    c.maxWidth / sceneSize.width,
                    c.maxHeight / sceneSize.height,
                  )
                  .clamp(0.08, 150.0);
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
        }
        final territory = <String, Path>{};
        for (final id in {
          ...adjacent,
          ...widget.game.owned,
          ...widget.game.progress.keys,
        }) {
          territory[id] = _path(widget.data.atlas.towns[id]!.polygons);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: transform,
                minScale: 0.08,
                maxScale: 150,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(2000),
                child: GestureDetector(
                  onTapUp: (details) {
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
                    child: CustomPaint(
                      painter: _NationalPainter(
                        paths,
                        labelBounds,
                        territory,
                        widget.data,
                        widget.game,
                        adjacent,
                        transform,
                        widget.onPrefectureSelected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Text(
                '全国 · 都道府県を選択',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
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
                            (control) => [control, const SizedBox(height: 2)],
                          ),
                          IconButton.filledTonal(
                            tooltip: '拡大',
                            onPressed: () => _zoom(1.7),
                            icon: const Icon(Icons.add),
                          ),
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
            if (error != null)
              Positioned(
                left: 8,
                top: 35,
                child: TextButton(
                  onPressed: _loadTerritory,
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
    this.onPrefectureSelected,
  ) : super(repaint: transform);
  final Map<String, Path> paths, territory;
  final Map<String, Rect> labelBounds;
  final NationalAtlas data;
  final Game game;
  final Set<String> adjacent;
  final TransformationController transform;
  final ValueChanged<String> onPrefectureSelected;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
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
    for (final path in paths.values) {
      canvas.drawPath(path, Paint()..color = const Color(0xFF43616A));
    }
    // Only town shapes receive ownership and progress colors; prefectures stay neutral.
    for (final e in territory.entries) {
      canvas.drawPath(
        e.value,
        Paint()
          ..color = townFillColor(
            data.atlas.towns[e.key]!,
            game,
            reachable: adjacent.contains(e.key),
          ),
      );
    }
    for (final e in paths.entries) {
      canvas.drawPath(
        e.value,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7 / zoom
          ..color = Colors.white,
      );
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
    }
  }

  @override
  bool shouldRepaint(_NationalPainter old) => true;
}

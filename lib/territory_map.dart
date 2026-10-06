import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game.dart';

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
  });
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
  final int focusVersion;
  final ValueChanged<String> onSelected, onCitySelected;
  @override
  State<TerritoryMap> createState() => _TerritoryMapState();
}

class _TerritoryMapState extends State<TerritoryMap> {
  final controller = TransformationController();
  late Map<String, Path> paths;
  late Map<String, Rect> bounds;
  late Map<String, Path> cityPaths;
  late Map<String, Rect> cityBounds;
  Size? viewport;
  static const mapSize = Size(1100, 1500);
  @override
  void initState() {
    super.initState();
    _buildPaths();
    _buildCities();
  }

  @override
  void dispose() {
    controller.dispose();
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
    Offset project(math.Point<double> p) =>
        Offset(dx + (p.x - minX) * 0.826 * scale, dy + (maxY - p.y) * scale);
    paths = {};
    bounds = {};
    for (final t in widget.atlas.towns.values) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final polygon in t.polygons) {
        for (final ring in polygon) {
          if (ring.isEmpty) continue;
          final start = project(ring.first);
          path.moveTo(start.dx, start.dy);
          for (final p in ring.skip(1)) {
            final o = project(p);
            path.lineTo(o.dx, o.dy);
          }
          path.close();
        }
      }
      paths[t.id] = path;
      bounds[t.id] = path.getBounds();
    }
  }

  void _buildCities() {
    cityPaths = {};
    cityBounds = {};
    for (final city in widget.atlas.byCity.entries) {
      final outline = _union(city.value.map((t) => paths[t.id]!).toList());
      cityPaths[city.key] = outline;
      cityBounds[city.key] = outline.getBounds();
    }
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
    if (old.cityId != widget.cityId ||
        old.focusVersion != widget.focusVersion) {
      _fit();
    }
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
                      widget.cityId == null ? cityBounds : bounds,
                      widget.atlas,
                      widget.game,
                      widget.selected,
                      controller,
                      widget.cityId,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 8,
            left: 14,
            child: Column(
              children: [
                Icon(
                  Icons.navigation_outlined,
                  size: 22,
                  color: Colors.white54,
                ),
                Text(
                  'N',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 8,
            child: Column(
              children: [
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

class _MapPainter extends CustomPainter {
  _MapPainter(
    this.paths,
    this.bounds,
    this.atlas,
    this.game,
    this.selected,
    this.transform,
    this.cityId,
  ) : super(repaint: transform);
  final TransformationController transform;
  final Map<String, Path> paths;
  final Map<String, Rect> bounds;
  final Atlas atlas;
  final Game game;
  final String? selected, cityId;
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
          ..color = const Color(0xFF102A32)
          ..strokeWidth = 1 / zoom;
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
              owned
                  ? const Color(0xFF7AE1BB)
                  : reachable
                  ? const Color(0xFFEEC47C)
                  : const Color(0xFF43616A),
      );
      canvas.drawPath(e.value, stroke);
      if (!overview && e.key == selected) {
        canvas.drawPath(
          e.value,
          Paint()..color = Colors.white.withValues(alpha: 0.2),
        );
        canvas.drawPath(
          e.value,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / zoom
            ..color = Colors.white,
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
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (overview ||
          e.key == selected ||
          (label.width < box.width && label.height < box.height)) {
        label.paint(
          canvas,
          box.center - Offset(label.width / 2, label.height / 2),
        );
      }
    }
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
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}

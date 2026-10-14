import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game.dart';
import 'national_atlas.dart';
import 'territory_map.dart';

class NationalMap extends StatefulWidget {
  const NationalMap({
    super.key,
    required this.data,
    required this.game,
    required this.onPrefectureSelected,
    this.controls = const [],
  });
  final NationalAtlas data;
  final Game game;
  final ValueChanged<String> onPrefectureSelected;
  final List<Widget> controls;
  @override
  State<NationalMap> createState() => _NationalMapState();
}

class _NationalMapState extends State<NationalMap> {
  final transform = TransformationController();
  final paths = <String, Path>{};
  bool initialized = false;
  String? error;
  late final Offset Function(math.Point<double>) project;

  @override
  void initState() {
    super.initState();
    // A common projection retains Hokkaido and the southern islands in one scene.
    project = (p) => Offset(40 + (p.x - 122) * 42, 40 + (46 - p.y) * 50);
    for (final p in widget.data.prefectures.values) {
      paths[p.id] = _path(p.polygons);
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

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (!initialized) {
        initialized = true;
        final scale = math.min(c.maxWidth / 1140, c.maxHeight / 1300);
        transform.value =
            Matrix4.identity()
              ..translate(
                (c.maxWidth - 1140 * scale) / 2,
                (c.maxHeight - 1300 * scale) / 2,
              )
              ..scale(scale);
      }
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
              minScale: 0.05,
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
                  width: 1140,
                  height: 1300,
                  child: CustomPaint(
                    painter: _NationalPainter(
                      paths,
                      territory,
                      widget.data,
                      widget.game,
                      adjacent,
                      transform,
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
            right: 8,
            top: 8,
            child: Column(children: widget.controls),
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
  );
}

class _NationalPainter extends CustomPainter {
  _NationalPainter(
    this.paths,
    this.territory,
    this.data,
    this.game,
    this.adjacent,
    this.transform,
  ) : super(repaint: transform);
  final Map<String, Path> paths, territory;
  final NationalAtlas data;
  final Game game;
  final Set<String> adjacent;
  final TransformationController transform;
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
      final bounds = e.value.getBounds();
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

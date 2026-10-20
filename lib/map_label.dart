import 'package:flutter/material.dart';

/// A crisp, screen-sized halo keeps geography names readable on every territory.
void paintMapLabel(
  Canvas canvas,
  TextPainter text,
  Offset position,
  double zoom,
) {
  final span = text.text! as TextSpan;
  final halo = TextPainter(
    text: TextSpan(
      text: span.text,
      style: span.style!.copyWith(
        foreground:
            Paint()
              ..color = const Color(0xFF102A32)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5 / zoom
              ..strokeJoin = StrokeJoin.round,
      ),
    ),
    textDirection: text.textDirection,
  )..layout();
  halo.paint(canvas, position);
  text.paint(canvas, position);
  halo.dispose();
}

/// Bounded native paragraph ownership for town labels. Pan does not recreate
/// text/halo paragraphs every frame; each map eagerly disposes these on exit.
class MapLabelCache {
  MapLabelCache({this.capacity = 128}) : assert(capacity > 0);
  final int capacity;
  final _labels = <(String, double), CachedMapLabel>{};
  Set<(String, double)> _needed = {};
  void beginFrame(Iterable<String> names, double zoom) {
    _needed = {for (final name in names) (name, zoom)};
  }

  void release(CachedMapLabel label) {
    if (!label.retained) label.dispose();
  }

  int created = 0;
  int get length => _labels.length;
  CachedMapLabel obtain(String name, double zoom) {
    final key = (name, zoom);
    final existing = _labels.remove(key);
    if (existing != null) {
      _labels[key] = existing;
      return existing;
    }
    if (_labels.length >= capacity) {
      final unused =
          _labels.keys.where((key) => !_needed.contains(key)).firstOrNull;
      if (unused == null) {
        // Keep the current visible set stable. Three overflowing labels must
        // not evict 128 reusable labels and cause a full-layout cycle per frame.
        created++;
        return CachedMapLabel(name, zoom, retained: false);
      }
      _labels.remove(unused)!.dispose();
    }
    final label = CachedMapLabel(name, zoom);
    created++;
    _labels[key] = label;
    return label;
  }

  void dispose() {
    for (final label in _labels.values) {
      label.dispose();
    }
    _labels.clear();
    _needed.clear();
  }
}

class CachedMapLabel {
  CachedMapLabel(String name, double zoom, {this.retained = true}) {
    final style = TextStyle(
      fontFamily: 'NotoSansJP',
      fontSize: 12 / zoom,
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );
    text = TextPainter(
      text: TextSpan(text: name, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    halo = TextPainter(
      text: TextSpan(
        text: name,
        style: style.copyWith(
          foreground:
              Paint()
                ..color = const Color(0xFF102A32)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5 / zoom
                ..strokeJoin = StrokeJoin.round,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
  final bool retained;
  late final TextPainter text, halo;
  double get width => text.width;
  double get height => text.height;
  void paint(Canvas canvas, Offset offset) {
    halo.paint(canvas, offset);
    text.paint(canvas, offset);
  }

  void dispose() {
    text.dispose();
    halo.dispose();
  }
}

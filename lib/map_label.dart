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

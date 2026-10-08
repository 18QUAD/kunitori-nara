import 'package:flutter/material.dart';

/// GSI map notation: double circle for city halls, single circle for town/village halls.
void paintOfficeSymbol(
  Canvas canvas,
  Offset center,
  double zoom, {
  required bool isCity,
  bool ready = false,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(1 / zoom);
  canvas.drawCircle(Offset.zero, 9, Paint()..color = const Color(0xEE101C2B));
  final stroke =
      Paint()
        ..color = ready ? const Color(0xFFEEC47C) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
  canvas.drawCircle(Offset.zero, 6, stroke);
  if (isCity) canvas.drawCircle(Offset.zero, 3, stroke);
  canvas.restore();
}

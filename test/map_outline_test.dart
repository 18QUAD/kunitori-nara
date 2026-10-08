import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_outline.dart';

void main() {
  test('omit internal contours while preserving detached exterior parts', () {
    final source =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(0, 0, 100, 100))
          ..addRect(const Rect.fromLTWH(20, 20, 10, 10))
          ..addRect(const Rect.fromLTWH(60, 60, 5, 5))
          ..addRect(const Rect.fromLTWH(150, 0, 20, 20));
    final outline = exteriorOutline(source);
    expect(outline.computeMetrics().length, 2);
    expect(outline.getBounds(), source.getBounds());
    expect(outline.contains(const Offset(160, 10)), isTrue);
    expect(source.contains(const Offset(25, 25)), isFalse);
    expect(source.computeMetrics().length, 4);
  });

  test('keep a detached part in the concavity of another exterior', () {
    final source =
        Path()
          ..moveTo(0, 0)
          ..lineTo(100, 0)
          ..lineTo(100, 20)
          ..lineTo(20, 20)
          ..lineTo(20, 100)
          ..lineTo(0, 100)
          ..close()
          ..addRect(const Rect.fromLTWH(60, 60, 10, 10));
    expect(exteriorOutline(source).computeMetrics().length, 2);
  });
}

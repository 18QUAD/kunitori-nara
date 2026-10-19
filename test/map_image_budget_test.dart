import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_image_budget.dart';

void main() {
  test('background and boundary reservations share one selected budget', () {
    for (final mb in [32, 64, 128, 256]) {
      final budget = MapImageBudget()..configure(mb);
      final half = budget.limit(MapImageKind.background) ~/ 2;
      expect(budget.reserve('a', MapImageKind.background, half), isTrue);
      expect(budget.reserve('b', MapImageKind.boundary, half), isTrue);
      expect(budget.reserve('c', MapImageKind.source, 1), isFalse);
      expect(
        budget.retainedBytes + budget.compressedBytes,
        mb * MapImageBudget.mib,
      );
      budget.release('a');
      expect(budget.reserve('c', MapImageKind.boundary, half), isTrue);
      budget.dispose();
    }
  });

  test('retiring pixels stay charged until their disposal finishes', () {
    final budget = MapImageBudget();
    final outgoing = Object(), incoming = Object();
    final capacity = budget.limit(MapImageKind.background);
    expect(budget.reserve(outgoing, MapImageKind.background, capacity), isTrue);
    expect(
      budget.reserve(incoming, MapImageKind.background, MapImageBudget.mib),
      isFalse,
    );
    budget.release(outgoing);
    expect(
      budget.reserve(incoming, MapImageKind.background, MapImageBudget.mib),
      isTrue,
    );
    expect(budget.used(MapImageKind.background), MapImageBudget.mib);
    budget.dispose();
  });

  test(
    'lowering the budget cannot admit more images while over its new share',
    () {
      final budget = MapImageBudget()..configure(256);
      final old = Object();
      expect(
        budget.reserve(old, MapImageKind.source, 32 * MapImageBudget.mib),
        isTrue,
      );
      budget.configure(32);
      expect(budget.reserve(Object(), MapImageKind.source, 1), isFalse);
      budget.release(old);
      expect(
        budget.reserve(Object(), MapImageKind.source, 256 * 256 * 4),
        isTrue,
      );
      expect(() => budget.configure(8), throwsArgumentError);
      budget.dispose();
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/map_image_budget.dart';

void main() {
  test('all four image pools together fit each selected budget', () {
    for (final mb in [32, 64, 128, 256]) {
      final budget = MapImageBudget()..configure(mb);
      for (final kind in MapImageKind.values) {
        expect(budget.reserve(kind, kind, budget.limit(kind)), isTrue);
        expect(budget.reserve(Object(), kind, 1), isFalse);
      }
      expect(
        budget.retainedBytes + budget.compressedBytes,
        mb * MapImageBudget.mib,
      );
      expect(
        budget.used(MapImageKind.background),
        greaterThanOrEqualTo(
          budget.rasterCells(MapImageKind.background) * MapImageBudget.mib,
        ),
      );
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

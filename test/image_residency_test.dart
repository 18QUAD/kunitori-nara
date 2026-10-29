import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_image_budget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('speculation cannot reclaim retained images', () async {
    final cache = GeographyImageCache(capacity: 2);
    // Cache admission happens before reading packed assets, so a full cache
    // can be verified without loading the national map archive.
    final budget = MapImageBudget.shared;
    final reservation = Object();
    expect(budget.reserve(reservation, MapImageKind.source,
        budget.limit(MapImageKind.source)), true);
    try {
      expect(cache.canPrefetch, false);
      await expectLater(cache.load('test_background', prefetch: true), throwsStateError);
      expect(budget.retainedBytes, budget.limit(MapImageKind.source));
      expect(cache.length, 0);
    } finally {
      budget.release(reservation);
    }
    expect(cache.canPrefetch, true);
  });
}

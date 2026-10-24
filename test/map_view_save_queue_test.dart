import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/map_view.dart';
import 'package:kunitori/map_view_save_queue.dart';
import 'package:kunitori/save_store.dart';

MapViewState view(int index) => MapViewState(
  center: Offset(index.toDouble(), 20),
  scale: 1.28,
  selected: null,
  cityId: null,
  nationalView: true,
);

void main() {
  testWidgets('100 pan updates persist the last view once after settling', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SaveStore(prefs);
    var writes = 0, rebuilds = 0;
    store.onChanged = () => rebuilds++;
    final queue = MapViewSaveQueue((v) {
      writes++;
      return store.saveMapView(v);
    });
    for (var i = 0; i < 100; i++) {
      queue.schedule(view(i));
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(writes, 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(writes, 1);
    expect(prefs.getString(SaveStore.mapViewKey), contains('99.0'));
    expect(
      rebuilds,
      0,
      reason: 'Successful camera writes do not rebuild the game',
    );
    queue.dispose();
  });

  testWidgets(
    'continuous pan writes at most once per second and retains the last position',
    (tester) async {
      final saved = <MapViewState>[];
      final queue = MapViewSaveQueue((v) async {
        saved.add(v);
      });
      for (var i = 0; i < 120; i++) {
        queue.schedule(view(i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(saved.length, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(saved.length, 2);
      expect(saved.last.center.dx, 119);
      queue.dispose();
    },
  );

  testWidgets(
    'background flush and disposal save immediately without later timer writes',
    (tester) async {
      final saved = <MapViewState>[];
      final queue = MapViewSaveQueue((v) async {
        saved.add(v);
      });
      queue.schedule(view(1));
      await queue.flush();
      expect(saved.single.center.dx, 1);
      queue.schedule(view(2));
      queue.dispose();
      expect(saved.last.center.dx, 2);
      queue.schedule(view(3));
      await tester.pump(const Duration(seconds: 2));
      expect(saved.length, 2);
    },
  );

  testWidgets(
    'reset cancels an obsolete camera save; clearing a save error still notifies',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SaveStore(prefs);
      var notifications = 0;
      store.onChanged = () => notifications++;
      final queue = MapViewSaveQueue(store.saveMapView);
      queue.schedule(view(1));
      queue.cancel();
      await tester.pump(const Duration(seconds: 2));
      expect(prefs.getString(SaveStore.mapViewKey), isNull);
      store.error = 'previous failure';
      await store.saveMapView(view(2));
      expect(store.error, isNull);
      expect(notifications, 1);
      queue.dispose();
    },
  );
}

import 'prepared_map_assets.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/geography_tiles.dart';
import 'package:kunitori/map_image_budget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GeographyTileIndex.load());
  testWidgets(
    'zoom round trips reuse images and game rebuilds initiate no loads',
    (tester) async {
      final cache = GeographyImageCache.shared;
      cache.clearUnused();
      final transform =
          TransformationController()..value = (Matrix4.identity()..scale(4.0));
      final clip = Path()..addRect(const Rect.fromLTWH(0, 0, 1000, 1000));
      Offset project(math.Point<double> p) =>
          Offset((p.x - 135.5) * 128, (35 - p.y) * 128);
      final events = <bool>[];
      Widget map() => MaterialApp(
        home: GeographyTiles(
          transform: transform,
          project: project,
          viewport: const Size(200, 200),
          clip: clip,
          enabled: true,
          onBusyChanged: events.add,
        ),
      );
      Future<void> finish() async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (events.isNotEmpty && !events.last) break;
        }
        expect(events.last, false);
        expect(tester.takeException(), isNull);
        expect(cache.diagnosticCounts['runtimeRasters'], 0);
        expect(
          MapImageBudget.shared.retainedBytes +
              MapImageBudget.shared.compressedBytes,
          lessThanOrEqualTo(32 * MapImageBudget.mib),
        );
      }

      await tester.pumpWidget(map());
      await finish();
      final warm = cache.diagnosticCounts['decodes'];
      final eventCount = events.length;
      await tester.pumpWidget(map());
      await tester.pump(const Duration(seconds: 1));
      expect(
        events.length,
        eventCount,
        reason:
            'An unchanged map rebuilt after a game tap must not start image work',
      );
      expect(cache.diagnosticCounts['decodes'], warm);
      transform.value = Matrix4.identity()..scale(8.0);
      await finish();
      final afterZoom = cache.diagnosticCounts['decodes'];
      transform.value = Matrix4.identity()..scale(4.0);
      await finish();
      expect(
        cache.diagnosticCounts['decodes'],
        afterZoom,
        reason: 'Returning to a retained adjacent level must decode nothing',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(retireMapImages);
      expect(
        cache.length,
        greaterThan(0),
        reason: 'Navigation must preserve the warm LRU',
      );
      cache.clearUnused();
      transform.dispose();
    },
  );

  testWidgets(
    'transient disk read failures retry automatically without extra UI',
    (tester) async {
      GeographyImageCache.shared.clearUnused();
      final transform =
          TransformationController()..value = (Matrix4.identity()..scale(4.0));
      final manifest = jsonDecode(
        File('data/prepared_maps/map-image-manifest.json').readAsStringSync(),
      );
      final asset = (manifest['assets'] as List).indexWhere(
        (e) => e[0] == '3_31_26_background.webp',
      );
      final pack = (manifest['packs'] as List).firstWhere(
        (p) => p[3] <= asset && asset < p[4],
      );
      final failingPath = 'data/prepared_maps/${pack[0]}';
      var failures = 0;
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (message) async {
          final name = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (name == failingPath && failures < 2) {
            failures++;
            return null;
          }
          if (name.startsWith('assets/data/map_images/')) {
            return preparedMapBytes(name).buffer.asByteData();
          }
          final file = File(name);
          return file.existsSync()
              ? (await file.readAsBytes()).buffer.asByteData()
              : null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        ),
      );
      final events = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: GeographyTiles(
            transform: transform,
            project: (p) => Offset((p.x - 135.5) * 128, (35 - p.y) * 128),
            viewport: const Size(200, 200),
            clip: Path()..addRect(const Rect.fromLTWH(0, 0, 1000, 1000)),
            enabled: true,
            onBusyChanged: events.add,
          ),
        ),
      );
      for (var i = 0; i < 250; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (events.where((b) => b).length >= 3 && events.last == false) break;
      }
      expect(failures, 2);
      expect(events.where((b) => b).length, 3);
      expect(events.last, false);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      GeographyImageCache.shared.clearUnused();
      transform.dispose();
    },
  );
}

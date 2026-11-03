import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/territory_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'tap progress repaints its town without invalidating ownership geometry',
    () async {
      final a = Atlas.fromJson(
        jsonDecode(File('assets/data/nara.json').readAsStringSync()),
      );
      final home = a.towns.values.firstWhere(
        (t) => t.neighbors.any((id) => a.towns[id]!.population > 100),
      );
      final target = home.neighbors.firstWhere(
        (id) => a.towns[id]!.population > 100,
      );
      final g = Game(a)..setHome(home.id);
      g.selectAttackTarget(target);
      g.progress[target] = 1;
      final paths = {
        target: Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100)),
        home.id: Path()..addRect(const Rect.fromLTWH(100, 0, 100, 100)),
      };
      final before = TownProgressPainter(g, paths, opacity: .55);
      g.progress[target] = (a.towns[target]!.population / 10).ceil();
      final after = TownProgressPainter(g, paths, opacity: .55);
      expect(after.snapshot.sameOwnership(before.snapshot), true);
      expect(after.shouldRepaint(before), true);
      g.progress[target] = g.progress[target]! + 1;
      expect(
        TownProgressPainter(g, paths, opacity: .55).shouldRepaint(after),
        false,
      );
      final recorder = ui.PictureRecorder();
      after.paint(Canvas(recorder), const Size(200, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 100);
      final bytes = (await image.toByteData())!;
      expect(bytes.getUint8((10 * 200 + 10) * 4 + 3), greaterThan(0));
      expect(
        bytes.getUint8((10 * 200 + 150) * 4 + 3),
        0,
        reason: 'unrelated owned town must not be drawn in progress layer',
      );
      image.dispose();
      picture.dispose();
      final old = TownProgressPainter(g, paths);
      g.owned.add(target);
      g.progress.remove(target);
      final captured = TownProgressPainter(g, paths);
      expect(captured.snapshot.sameOwnership(old.snapshot), false);
      expect(captured.shouldRepaint(old), true);
    },
  );
}

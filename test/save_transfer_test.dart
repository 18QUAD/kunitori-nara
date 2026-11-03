import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kunitori/game.dart';
import 'package:kunitori/save_store.dart';
import 'package:kunitori/save_transfer.dart';
import 'package:kunitori/tip_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Atlas atlas;
  setUpAll(() {
    atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  test(
    'portable save preserves game progress and appearance with checksum',
    () {
      final game = Game(atlas)..setHome(atlas.byCity['29202']!.first.id);
      game.totalTaps = 12345;
      final values = <String, String?>{
        SaveStore.key: jsonEncode(game.toJson()),
        SaveStore.mapViewKey: null,
        TipAppearanceStore.key: jsonEncode(const TipAppearance().toJson()),
      };
      final code = SaveTransfer.encode(values);
      expect(SaveTransfer.decode('\n$code\n'), values);
      final restored = Game.restore(
        atlas,
        jsonDecode(SaveTransfer.decode(code)[SaveStore.key]!)
            as Map<String, dynamic>,
      );
      expect(restored.toJson(), game.toJson());
      expect(
        () => SaveTransfer.decode('${code.substring(0, code.length - 1)}x'),
        throwsFormatException,
      );
      expect(
        () => SaveTransfer.decode('KNTR2.${code.split('.').skip(1).join('.')}'),
        throwsFormatException,
      );
      expect(() => SaveTransfer.decode('incomplete'), throwsFormatException);
    },
  );
  test(
    'import retains durable previous save and supports restoring backup',
    () async {
      final a = Game(atlas)..setHome(atlas.byCity['29202']!.first.id);
      final b = Game(atlas)..setHome(atlas.byCity['29206']!.first.id);
      SharedPreferences.setMockInitialValues({
        SaveStore.key: jsonEncode(a.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final previous = SaveTransfer.snapshot(prefs);
      final incoming = {...previous, SaveStore.key: jsonEncode(b.toJson())};
      await SaveTransfer.install(prefs, incoming);
      expect(SaveStore(prefs).load(atlas).home, b.home);
      final backup = SaveTransfer.decode(
        prefs.getString(SaveTransfer.backupKey)!,
      );
      expect(backup, previous);
      await SaveTransfer.install(prefs, backup);
      expect(SaveStore(prefs).load(atlas).home, a.home);
    },
  );
}

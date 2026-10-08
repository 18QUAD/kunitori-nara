import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every displayed tip fits two lines on a 320px phone', () async {
    final font = FontLoader('NotoSansJP')
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP.ttf'));
    await font.load();
    final atlas = Atlas.fromJson(
      jsonDecode(File('assets/data/nara.json').readAsStringSync()),
    );
    final game = Game(atlas);
    for (final city in atlas.cities.keys) {
      for (final fact in game.tipsFor(selectedCity: city)) {
        final painter = TextPainter(
          text: TextSpan(
            text: fact.text,
            style: const TextStyle(
              fontFamily: 'NotoSansJP',
              fontSize: 14,
              height: 1.5,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
        )..layout(maxWidth: 320 - 24);
        expect(painter.didExceedMaxLines, isFalse, reason: fact.text);
        expect(painter.height, lessThanOrEqualTo(44), reason: fact.text);
        painter.dispose();
      }
    }
  });
}

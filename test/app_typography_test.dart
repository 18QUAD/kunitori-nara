import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/app_typography.dart';

Future<(double, int)> paintLabel(String family, int weight) async {
  final painter = TextPainter(
    text: TextSpan(
      text: '城陽市 46,071 / 74,607  京都府',
      style: TextStyle(
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        fontVariations:
            family == 'BrowserReference'
                ? [FontVariation('wght', weight.toDouble())]
                : null,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  painter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (painter.width * 2).ceil() + 2,
    (painter.height * 2).ceil() + 2,
  );
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var ink = 0;
  for (var i = 3; i < data.lengthInBytes; i += 4) {
    ink += data.getUint8(i);
  }
  final width = painter.width;
  painter.dispose();
  picture.dispose();
  image.dispose();
  return (width, ink);
}

void main() {
  setUpAll(() async {
    final native = FontLoader('KunitoriNotoJP');
    for (final weight in [400, 500, 600, 700, 900]) {
      native.addFont(
        rootBundle.load('assets/fonts/NotoSansJPNative-$weight.ttf'),
      );
    }
    await native.load();
    await (FontLoader('BrowserReference')
      ..addFont(rootBundle.load('assets/fonts/NotoSansJP.ttf'))).load();
  });

  for (final weight in [400, 500, 600, 700, 900]) {
    test(
      'native weight $weight matches browser glyph width and stroke',
      () async {
        expect(appFontFamily, 'KunitoriNotoJP');
        final (nativeWidth, nativeInk) = await paintLabel(
          appFontFamily,
          weight,
        );
        final (browserWidth, browserInk) = await paintLabel(
          'BrowserReference',
          weight,
        );
        expect(nativeWidth, closeTo(browserWidth, .1));
        expect(browserInk, greaterThan(0));
        // Compare actual glyph coverage, so accidentally registering the source
        // font's thin default fails even when fontSize/fontWeight look correct.
        expect(nativeInk / browserInk, closeTo(1, .03));
      },
    );
  }
}

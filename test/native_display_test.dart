import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/main.dart';
import 'package:kunitori/native_display.dart';

void main() {
  for (final factor in [.8, 1.0, 1.5]) {
    testWidgets(
      'app applies readable text at system scale $factor',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(factor),
              ),
              child: Builder(
                builder: (context) {
                  final app = const KunitoriApp().build(context) as MaterialApp;
                  return app.builder!(
                    context,
                    const Text('寺田の案内', style: TextStyle(fontSize: 16)),
                  );
                },
              ),
            ),
          ),
        );
        final text = tester.widget<RichText>(find.byType(RichText));
        expect(text.textScaler.scale(16), factor < 1 ? 16 : 16 * factor);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.mobile(),
    );
  }

  test('native text never falls below the browser baseline', () {
    final scaler = displayTextScaler(const TextScaler.linear(.8), isWeb: false);
    for (final size in [12.0, 13.0, 16.0, 22.0]) {
      expect(scaler.scale(size), size);
    }
  });

  test('native preserves normal and enlarged accessible text', () {
    for (final factor in [1.0, 1.5, 2.0]) {
      final scaler = displayTextScaler(TextScaler.linear(factor), isWeb: false);
      expect(scaler.scale(16), 16 * factor);
    }
  });

  test('web text scaling is unchanged', () {
    final system = const TextScaler.linear(.8);
    expect(displayTextScaler(system, isWeb: true), same(system));
  });
}

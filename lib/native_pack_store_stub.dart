import 'dart:typed_data';

Future<Uint8List> loadNativePack(Uri url, String digest, int size) =>
    throw UnsupportedError('Native map packs are unavailable on web.');

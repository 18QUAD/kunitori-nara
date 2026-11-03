import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<void> _queue = Future<void>.value();
Future<Directory>? _directory;
const _diskBudget = 512 * 1024 * 1024;

/// Serialize downloads to bound transient memory independently of tile count.
Future<Uint8List> loadNativePack(Uri url, String digest, int size) {
  final result = _queue.then((_) => _load(url, digest, size));
  _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  return result;
}

Future<Uint8List> _load(Uri url, String digest, int size) async {
  if (url.scheme != 'https' ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
      size <= 0 ||
      size > 1024 * 1024) {
    throw const FormatException('地図パックの形式が不正です。');
  }
  final directory =
      await (_directory ??= getApplicationSupportDirectory().then(
        (root) =>
            Directory('${root.path}/map-packs-v1').create(recursive: true),
      ));
  final file = File('${directory.path}/$digest.bin');
  bool valid(Uint8List bytes) =>
      bytes.length == size && sha256.convert(bytes).toString() == digest;
  if (await file.exists()) {
    if (await file.length() == size) {
      final bytes = await file.readAsBytes();
      if (valid(bytes)) {
        await file.setLastModified(DateTime.now());
        return bytes;
      }
    }
    await file.delete();
  }
  final client = http.Client();
  late Uint8List bytes;
  try {
    final response = await client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 ||
        (response.contentLength != null && response.contentLength != size)) {
      throw const HttpException('地図を取得できませんでした。');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (builder.length + chunk.length > size)
        throw const FormatException('地図パックが大きすぎます。');
      builder.add(chunk);
    }
    bytes = builder.takeBytes();
    if (!valid(bytes)) throw const FormatException('地図パックの検証に失敗しました。');
  } finally {
    client.close();
  }
  final temporary = File('${file.path}.part');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.bin')) continue;
      final stat = await entry.stat();
      total += stat.size;
      if (entry.path != file.path) files.add((entry, stat));
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in files) {
      if (total <= _diskBudget) break;
      await entry.$1.delete();
      total -= entry.$2.size;
    }
  } on FileSystemException {
    // A full disk must not prevent play with an already verified download.
    try {
      if (await temporary.exists()) await temporary.delete();
    } catch (_) {}
  }
  return bytes;
}

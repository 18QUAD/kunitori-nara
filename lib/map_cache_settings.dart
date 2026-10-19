import 'package:flutter/material.dart';
import 'map_cache_bridge.dart';

class MapCacheSettings extends StatefulWidget {
  const MapCacheSettings({super.key});
  @override
  State<MapCacheSettings> createState() => _MapCacheSettingsState();
}

class _MapCacheSettingsState extends State<MapCacheSettings> {
  int? value;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    readMapCacheMegabytes()
        .then((result) {
          if (mounted) setState(() => value = result);
        })
        .catchError((Object _) {
          if (mounted) setState(() => error = '設定を読み込めませんでした');
        });
  }

  Future<void> change(int? next) async {
    if (next == null || next == value || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await saveMapCacheMegabytes(next);
      if (mounted) setState(() => value = next);
    } catch (_) {
      if (mounted) setState(() => error = '設定を保存できませんでした');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '地図キャッシュ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '閉じる',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Text('よく使う地図データをメモリに保持する容量です。'),
          for (final size in [32, 64, 128, 256])
            RadioListTile<int>(
              title: Text(size == 32 ? '32 MB（標準）' : '$size MB'),
              value: size,
              groupValue: value,
              onChanged: value == null || saving ? null : change,
            ),
          if (value == null && error == null || saving)
            const LinearProgressIndicator(),
          if (error != null) Text(error!),
        ],
      ),
    ),
  );
}

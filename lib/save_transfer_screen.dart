import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'save_transfer.dart';

class SaveTransferScreen extends StatefulWidget {
  const SaveTransferScreen({
    super.key,
    required this.exportCode,
    required this.preview,
    this.backup,
  });
  final String exportCode;
  final String? backup;
  final Future<String> Function(Map<String, String?>) preview;
  @override
  State<SaveTransferScreen> createState() => _SaveTransferScreenState();
}

class _SaveTransferScreenState extends State<SaveTransferScreen> {
  final _input = TextEditingController();
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _review(String code) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final values = SaveTransfer.decode(code);
      final summary = await widget.preview(values);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('引き継ぎ内容の確認'),
              content: Text(
                '$summary\n\n現在の進行をこのデータで置き換えます。取り込み前のデータは1件バックアップします。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('このデータを取り込む'),
                ),
              ],
            ),
      );
      if (yes == true && mounted) Navigator.pop(context, values);
    } catch (_) {
      if (mounted)
        setState(() => _message = 'コードを読み込めません。書き出したコードを省略せず貼り付けてください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('データ引き継ぎ')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'ブラウザ版の設定からコードをコピーし、アプリ版のこの画面に貼り付けてください。領土・タップ数・戦績・キャラ設定を引き継ぎます。自動同期はされません。',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed:
              _busy
                  ? null
                  : () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.exportCode),
                    );
                    if (mounted) setState(() => _message = '引き継ぎコードをコピーしました。');
                  },
          icon: const Icon(Icons.copy),
          label: const Text('現在のデータをコピー'),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('書き出したコードを表示'),
          children: [SelectableText(widget.exportCode)],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _input,
          minLines: 3,
          maxLines: 6,
          maxLength: SaveTransfer.maxLength,
          decoration: const InputDecoration(
            labelText: '引き継ぎコード',
            counterText: '',
          ),
          autocorrect: false,
        ),
        TextButton(
          onPressed:
              _busy
                  ? null
                  : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (mounted) _input.text = data?.text ?? '';
                  },
          child: const Text('クリップボードから貼り付け'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _review(_input.text),
          child: const Text('内容を確認して取り込む'),
        ),
        if (widget.backup != null)
          TextButton(
            onPressed: _busy ? null : () => _review(widget.backup!),
            child: const Text('取り込み前のバックアップを復元'),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!),
          ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'tip_appearance.dart';
import 'tip_presenter.dart';

class TipSettings extends StatefulWidget {
  const TipSettings({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final TipAppearance initial;
  final ValueChanged<TipAppearance> onChanged;
  @override
  State<TipSettings> createState() => _TipSettingsState();
}

class _TipSettingsState extends State<TipSettings> {
  late TipAppearance appearance = widget.initial;
  void update(TipAppearance value) {
    setState(() => appearance = value);
    widget.onChanged(value);
  }

  Widget choice<T>(
    String label,
    T value,
    List<T> values,
    String Function(T) name,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items:
          values
              .map((v) => DropdownMenuItem(value: v, child: Text(name(v))))
              .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.9,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'キャラ・吹き出し',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'tips設定を閉じる',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Container(
          key: const Key('tip-settings-preview'),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF122B32),
            borderRadius: BorderRadius.circular(18),
          ),
          child:
              appearance.showTips
                  ? TipPresenter(
                    text: '奈良公園の鹿は、国の天然記念物に指定されています。',
                    appearance: appearance,
                  )
                  : const SizedBox(
                    height: 48,
                    child: Center(child: Text('tipsは非表示です')),
                  ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('tipsを表示'),
                value: appearance.showTips,
                onChanged: (v) => update(appearance.copyWith(showTips: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('キャラを表示'),
                value: appearance.showCharacter,
                onChanged: (v) => update(appearance.copyWith(showCharacter: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('吹き出しを表示'),
                value: appearance.showBubble,
                onChanged: (v) => update(appearance.copyWith(showBubble: v)),
              ),
              const SizedBox(height: 16),
              choice(
                'キャラのデザイン',
                appearance.character,
                TipCharacter.values,
                (v) => v.label,
                (v) => update(appearance.copyWith(character: v)),
              ),
              choice(
                'キャラの位置',
                appearance.characterOnRight,
                const [false, true],
                (v) => v ? '右' : '左',
                (v) => update(appearance.copyWith(characterOnRight: v)),
              ),
              choice(
                '吹き出しの色',
                appearance.bubbleStyle,
                TipBubbleStyle.values,
                (v) => v.label,
                (v) => update(appearance.copyWith(bubbleStyle: v)),
              ),
              choice(
                '吹き出しの形',
                appearance.bubbleShape,
                TipBubbleShape.values,
                (v) => v.label,
                (v) => update(appearance.copyWith(bubbleShape: v)),
              ),
              choice(
                '表示サイズ',
                appearance.size,
                TipSize.values,
                (v) => v.label,
                (v) => update(appearance.copyWith(size: v)),
              ),
              OutlinedButton.icon(
                onPressed: () => update(const TipAppearance()),
                icon: const Icon(Icons.restore),
                label: const Text('表示設定を初期値に戻す'),
              ),
              const SizedBox(height: 12),
              const Text(
                '変更はすぐに反映され、この端末に保存されます。',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

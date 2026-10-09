import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum TipCharacter {
  guide('鹿の案内人'),
  deer('鹿マーク');

  const TipCharacter(this.label);
  final String label;
}

enum TipBubbleStyle {
  red('白地・枠なし'),
  gold('クリーム・金の縁'),
  mint('濃紺・ミントの縁');

  const TipBubbleStyle(this.label);
  final String label;
}

enum TipBubbleShape {
  speech('吹き出し'),
  rounded('丸角カード'),
  square('角形カード');

  const TipBubbleShape(this.label);
  final String label;
}

enum TipPlacement {
  mapBottom('地図の下部'),
  mapTop('地図の上部'),
  controls('操作欄の上');

  const TipPlacement(this.label);
  final String label;
}

enum TipSize {
  small('小さめ', 100, 12),
  standard('標準', 116, 13),
  large('大きめ', 132, 14);

  const TipSize(this.label, this.height, this.fontSize);
  final String label;
  final double height, fontSize;
}

class TipAppearance {
  const TipAppearance({
    this.showTips = true,
    this.showCharacter = true,
    this.showBubble = true,
    this.blinkEnabled = true,
    this.lipSyncEnabled = true,
    this.character = TipCharacter.guide,
    this.bubbleStyle = TipBubbleStyle.red,
    this.bubbleShape = TipBubbleShape.speech,
    this.placement = TipPlacement.mapBottom,
    this.characterOnRight = false,
    this.size = TipSize.standard,
    this.controlInsetSize,
  });
  final bool showTips, showCharacter, showBubble, characterOnRight;
  final bool blinkEnabled, lipSyncEnabled;
  final TipCharacter character;
  final TipBubbleStyle bubbleStyle;
  final TipBubbleShape bubbleShape;
  final TipPlacement placement;
  final TipSize size;
  // Preserve the former action height when moving a saved controls tip onto the map.
  final TipSize? controlInsetSize;

  TipAppearance copyWith({
    bool? showTips,
    bool? showCharacter,
    bool? showBubble,
    bool? blinkEnabled,
    bool? lipSyncEnabled,
    bool? characterOnRight,
    TipCharacter? character,
    TipBubbleStyle? bubbleStyle,
    TipBubbleShape? bubbleShape,
    TipPlacement? placement,
    TipSize? size,
  }) => TipAppearance(
    showTips: showTips ?? this.showTips,
    showCharacter: showCharacter ?? this.showCharacter,
    showBubble: showBubble ?? this.showBubble,
    blinkEnabled: blinkEnabled ?? this.blinkEnabled,
    lipSyncEnabled: lipSyncEnabled ?? this.lipSyncEnabled,
    characterOnRight: characterOnRight ?? this.characterOnRight,
    character: character ?? this.character,
    bubbleStyle: bubbleStyle ?? this.bubbleStyle,
    bubbleShape: bubbleShape ?? this.bubbleShape,
    placement: placement ?? this.placement,
    size: size ?? this.size,
    controlInsetSize: controlInsetSize,
  );

  Map<String, dynamic> toJson() => {
    'showTips': showTips,
    'showCharacter': showCharacter,
    'showBubble': showBubble,
    'blinkEnabled': blinkEnabled,
    'lipSyncEnabled': lipSyncEnabled,
    'characterOnRight': characterOnRight,
    'character': character.name,
    'bubbleStyle': bubbleStyle.name,
    'bubbleShape': bubbleShape.name,
    'placement': placement.name,
    'size': size.name,
    if (controlInsetSize != null) 'controlInsetSize': controlInsetSize!.name,
  };

  factory TipAppearance.fromJson(Map<String, dynamic> data) {
    T value<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == data[key]).firstOrNull ?? fallback;
    bool flag(String key, bool fallback) =>
        data[key] is bool ? data[key] as bool : fallback;
    return TipAppearance(
      showTips: flag('showTips', true),
      showCharacter: flag('showCharacter', true),
      showBubble: flag('showBubble', true),
      blinkEnabled: flag('blinkEnabled', true),
      lipSyncEnabled: flag('lipSyncEnabled', true),
      characterOnRight: flag('characterOnRight', false),
      character: value(TipCharacter.values, 'character', TipCharacter.guide),
      bubbleStyle: value(
        TipBubbleStyle.values,
        'bubbleStyle',
        TipBubbleStyle.red,
      ),
      bubbleShape: value(
        TipBubbleShape.values,
        'bubbleShape',
        TipBubbleShape.speech,
      ),
      placement: TipPlacement.mapBottom,
      size: value(TipSize.values, 'size', TipSize.standard),
      controlInsetSize:
          TipSize.values
              .where((v) => v.name == data['controlInsetSize'])
              .firstOrNull ??
          (data['placement'] == 'controls' && flag('showTips', true)
              ? value(TipSize.values, 'size', TipSize.standard)
              : null),
    );
  }
}

class TipAppearanceStore {
  TipAppearanceStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'kunitori.nara.tipAppearance.v1';
  Future<void> _writing = Future.value();
  TipAppearance load() {
    try {
      final raw = preferences.getString(key);
      return raw == null
          ? const TipAppearance()
          : TipAppearance.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
    } catch (_) {
      return const TipAppearance();
    }
  }

  Future<void> save(TipAppearance appearance) {
    _writing = _writing.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(key, jsonEncode(appearance.toJson()))) {
        throw StateError('表示設定を保存できませんでした');
      }
    });
    return _writing;
  }
}

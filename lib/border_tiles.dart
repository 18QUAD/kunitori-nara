import 'geography_tiles.dart';

/// Pre-rendered, scale-specific boundary images, independent of terrain toggle.
class BorderTiles extends GeographyTiles {
  const BorderTiles({
    super.key,
    required super.transform,
    required super.project,
    required super.viewport,
    required super.clip,
    required String layer,
    super.prefectureId,
    super.onBusyChanged,
  }) : super(enabled: true, boundaryLayer: layer);
}

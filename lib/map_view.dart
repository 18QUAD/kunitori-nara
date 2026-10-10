import 'package:flutter/material.dart';
import 'game.dart';

/// Store a scene center rather than screen pixels, so viewport changes keep it.
class MapViewState {
  const MapViewState({
    required this.center,
    required this.scale,
    required this.selected,
    required this.cityId,
    this.showGeography = true,
  });
  static const dataset = 'nara-2020-v1';
  static const projection = '1100x1500-v1';
  final Offset center;
  final double scale;
  final String? selected, cityId;
  final bool showGeography;

  Map<String, dynamic> toJson() => {
    'dataset': dataset,
    'projection': projection,
    'center': [center.dx, center.dy],
    'scale': scale,
    'selected': selected,
    'cityId': cityId,
    'showGeography': showGeography,
  };

  static MapViewState? fromJson(Map<String, dynamic> data, Atlas atlas) {
    if (data['dataset'] != dataset || data['projection'] != projection) {
      return null;
    }
    final point = data['center'];
    final zoom = data['scale'];
    final town = data['selected'];
    final city = data['cityId'];
    if (point is! List ||
        point.length != 2 ||
        point.any((v) => v is! num) ||
        zoom is! num ||
        (town != null && !atlas.towns.containsKey(town)) ||
        (city != null && !atlas.cities.containsKey(city))) {
      return null;
    }
    final x = (point[0] as num).toDouble(), y = (point[1] as num).toDouble();
    final scale = zoom.toDouble();
    if (!x.isFinite ||
        !y.isFinite ||
        x.abs() > 100000 ||
        y.abs() > 100000 ||
        !scale.isFinite ||
        scale < 0.08 ||
        scale > 150) {
      return null;
    }
    return MapViewState(
      center: Offset(x, y),
      scale: scale,
      selected: town as String?,
      cityId: city as String?,
      showGeography: data['showGeography'] != false,
    );
  }
}

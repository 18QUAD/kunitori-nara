import 'dart:math';

/// A geographic marker, independent of the offices that enable conquest quizzes.
class OfficeMarker {
  const OfficeMarker({
    required this.id,
    required this.cityId,
    required this.name,
    required this.address,
    required this.point,
    required this.isCity,
    this.townId,
  });
  final String id, cityId, name, address;
  final Point<double> point;
  final bool isCity;
  // Null for headquarters outside their municipality or census town boundaries.
  final String? townId;
}

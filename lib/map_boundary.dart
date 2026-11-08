import 'package:flutter/rendering.dart';

/// One administrative boundary shared by every layer in the map scene.
class MapBoundaryClipper extends CustomClipper<Path> {
  const MapBoundaryClipper(this.boundary);

  final Path boundary;

  @override
  Path getClip(Size size) => boundary;

  @override
  bool shouldReclip(MapBoundaryClipper oldClipper) =>
      oldClipper.boundary != boundary;
}

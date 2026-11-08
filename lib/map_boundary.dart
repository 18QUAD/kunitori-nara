import 'package:flutter/widgets.dart';

/// Clip geographic layers while keeping the final annotation layer intact.
class MapBoundaryScene extends StatelessWidget {
  const MapBoundaryScene({
    super.key,
    required this.boundary,
    required this.children,
  }) : assert(children.length >= 2);

  final Path boundary;
  // Terrain, ownership and borders precede the final label/office layer.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topLeft,
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: [
      ClipPath(
        clipper: MapBoundaryClipper(boundary),
        child: Stack(
          alignment: Alignment.topLeft,
          fit: StackFit.expand,
          children: children.sublist(0, children.length - 1),
        ),
      ),
      children.last,
    ],
  );
}

/// Administrative boundary for geographic content, excluding annotations.
class MapBoundaryClipper extends CustomClipper<Path> {
  const MapBoundaryClipper(this.boundary);

  final Path boundary;

  @override
  Path getClip(Size size) => boundary;

  @override
  bool shouldReclip(MapBoundaryClipper oldClipper) =>
      oldClipper.boundary != boundary;
}

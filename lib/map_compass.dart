import 'package:flutter/material.dart';

/// Maps are north-up at every scale.
class MapCompass extends StatelessWidget {
  const MapCompass({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      label: '北',
      child: const SizedBox(
        key: Key('map-compass'),
        width: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.navigation_outlined, size: 22, color: Colors.white),
            Text('N', style: TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

/// The campaign home control shares the map image worker's operation lock.
Widget lockMapHomeControl(Widget control, bool Function() isBusy) {
  if (control is! IconButton || control.key != const Key('map-home')) {
    return control;
  }
  return IconButton.filledTonal(
    key: control.key,
    tooltip: control.tooltip,
    icon: control.icon,
    onPressed:
        isBusy() || control.onPressed == null
            ? null
            : () {
              // Reject another tap even before the disabled frame is painted.
              if (!isBusy()) control.onPressed!();
            },
  );
}

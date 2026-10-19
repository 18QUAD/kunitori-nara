import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

Widget protectAttackTap({required Widget child, VoidCallback? onPressed}) =>
    MergeSemantics(
      child: Semantics(
        onTap: onPressed,
        child: Listener(
          key: const Key('attack'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if ((event.buttons & kPrimaryButton) != 0) onPressed?.call();
          },
          // The ordinary button still supplies appearance, keyboard activation
          // and its label. Its release gesture must not add a second tap.
          child: AbsorbPointer(child: child),
        ),
      ),
    );

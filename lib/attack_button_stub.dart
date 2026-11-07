import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'action_choices.dart';
import 'native_display.dart';

Widget protectAttackTap({required Widget child, VoidCallback? onPressed}) =>
    Builder(
      builder: (context) {
        if (ActionChoiceRegion.sideOf(context) != null) {
          return _ContactAttackButton(onPressed: onPressed, child: child);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: nativePortraitAttackHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final right in [false, true]) ...[
                  if (right) const SizedBox(width: nativePortraitAttackGap),
                  Expanded(
                    child: ActionChoiceRegion(
                      right: right,
                      child: _ContactAttackButton(
                        onPressed: onPressed,
                        child: child,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

class _ContactAttackButton extends StatefulWidget {
  const _ContactAttackButton({required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_ContactAttackButton> createState() => _ContactAttackButtonState();
}

class _ContactAttackButtonState extends State<_ContactAttackButton>
    with WidgetsBindingObserver {
  final _contacts = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _contacts.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      onTap: widget.onPressed,
      child: Listener(
        key: const Key('attack'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if ((event.buttons & kPrimaryButton) == 0) return;
          if (_contacts.add(event.pointer)) widget.onPressed?.call();
        },
        // Flutter routes releases and cancellations here even outside the box.
        onPointerUp: (event) => _contacts.remove(event.pointer),
        onPointerCancel: (event) => _contacts.remove(event.pointer),
        // Preserve button appearance, keyboard activation and its accessible
        // label without a second activation from the release gesture.
        child: AbsorbPointer(child: widget.child),
      ),
    ),
  );
}

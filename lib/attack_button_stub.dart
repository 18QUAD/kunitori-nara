import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

Widget protectAttackTap({required Widget child, VoidCallback? onPressed}) =>
    _ContactAttackButton(onPressed: onPressed, child: child);

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
          final first = _contacts.isEmpty;
          if (_contacts.add(event.pointer) && first) widget.onPressed?.call();
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

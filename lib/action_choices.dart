import 'package:flutter/material.dart';

/// Routes a two-choice action to the corresponding landscape side panel.
/// Without a side panel, choices share a row as they do in portrait.
class ActionChoiceRegion extends InheritedWidget {
  const ActionChoiceRegion({
    super.key,
    required this.right,
    required super.child,
  });
  final bool? right;

  static bool? sideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActionChoiceRegion>()?.right;

  @override
  bool updateShouldNotify(ActionChoiceRegion oldWidget) =>
      right != oldWidget.right;
}

class ActionChoices extends StatelessWidget {
  const ActionChoices({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final right = ActionChoiceRegion.sideOf(context);
    if (right != null) {
      if (children.isEmpty || (right && children.length < 2)) {
        return const SizedBox.shrink();
      }
      return SizedBox.expand(child: children[right ? 1 : 0]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'game.dart' show number;

/// Pulses only for new taps on the same town, without shifting the header.
class TapProgress extends StatefulWidget {
  const TapProgress({
    super.key,
    required this.townId,
    required this.value,
    required this.population,
    required this.tapCount,
  });
  final String townId;
  final int value, population, tapCount;

  @override
  State<TapProgress> createState() => _TapProgressState();
}

class _TapProgressState extends State<TapProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.13,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.13,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.reset();
  }

  @override
  void didUpdateWidget(TapProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.townId != oldWidget.townId) {
      _controller.reset();
    } else if (widget.tapCount > oldWidget.tapCount &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Padding(
      // Leave room for the pulse inside the width allocated by the header.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Semantics(
        label: '${number(widget.value)} / ${number(widget.population)}',
        child: ExcludeSemantics(
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Color(0xFFEEC47C),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontVariations: [FontVariation('wght', 900)],
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ScaleTransition(
                    key: const Key('tap-progress-pulse'),
                    scale: _scale,
                    child: Text(
                      number(widget.value),
                      key: const Key('attack-progress'),
                    ),
                  ),
                ),
                Text(
                  '/ ${number(widget.population)}',
                  key: const Key('attack-population'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

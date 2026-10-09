import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tip_appearance.dart';

class TipPresenter extends StatelessWidget {
  const TipPresenter({
    super.key,
    required this.text,
    required this.appearance,
    this.expandForText = false,
  });
  final String text;
  final TipAppearance appearance;
  final bool expandForText;

  @override
  Widget build(BuildContext context) {
    final a = appearance;
    if (!a.showTips) return const SizedBox.shrink();
    final (background, border, foreground) = switch (a.bubbleStyle) {
      TipBubbleStyle.red => (
        const Color(0xFFFFFAF5),
        Colors.transparent,
        const Color(0xFF242D36),
      ),
      TipBubbleStyle.gold => (
        const Color(0xFFFFF2D7),
        const Color(0xFFDFA545),
        const Color(0xFF382D20),
      ),
      TipBubbleStyle.mint => (
        const Color(0xFF192A3A),
        const Color(0xFF7AE1BB),
        Colors.white,
      ),
    };
    final hasTail =
        a.showBubble &&
        a.showCharacter &&
        a.bubbleShape == TipBubbleShape.speech;
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio =
            a.character == TipCharacter.guide ? 840 / 880 : 100 / 120;
        final availableHeight = math.min(a.size.height, constraints.maxHeight);
        final characterWidth = math.min(
          constraints.maxWidth / 4,
          availableHeight * aspectRatio,
        );
        var height =
            a.showCharacter ? characterWidth / aspectRatio : availableHeight;
        if (expandForText) {
          final measure = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(
                const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(
            maxWidth: math.max(
              1,
              constraints.maxWidth - characterWidth - (hasTail ? 10 : 0) - 20,
            ),
          );
          height = math.max(height, measure.height + 24);
          measure.dispose();
        }
        final bubble = Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(
              left: hasTail && !a.characterOnRight ? 10 : 0,
              right: hasTail && a.characterOnRight ? 10 : 0,
            ),
            child: CustomPaint(
              key: const Key('tip-bubble'),
              painter:
                  a.showBubble
                      ? _BubblePainter(
                        background,
                        border,
                        a.bubbleShape == TipBubbleShape.square ? 8 : 22,
                        hasTail,
                        a.characterOnRight,
                      )
                      : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: a.showBubble ? 10 : 0,
                  vertical: expandForText ? 12 : 4,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    var fontSize = expandForText ? 16.0 : a.size.fontSize;
                    TextStyle style() => TextStyle(
                      fontSize: fontSize,
                      height: expandForText ? 1.4 : 1.25,
                      fontWeight:
                          a.showBubble ? FontWeight.w600 : FontWeight.normal,
                      color: a.showBubble ? foreground : Colors.white,
                      shadows:
                          a.showBubble
                              ? null
                              : const [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                    );
                    while (!expandForText && fontSize > 10) {
                      final painter = TextPainter(
                        text: TextSpan(
                          text: text,
                          style: DefaultTextStyle.of(
                            context,
                          ).style.merge(style()),
                        ),
                        textDirection: Directionality.of(context),
                        maxLines: 4,
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout(maxWidth: constraints.maxWidth);
                      final fits =
                          !painter.didExceedMaxLines &&
                          painter.height <= constraints.maxHeight;
                      painter.dispose();
                      if (fits) break;
                      fontSize -= 0.5;
                    }
                    return Center(
                      child: Text(
                        text,
                        key: const Key('tip-text'),
                        maxLines: expandForText ? null : 4,
                        overflow:
                            expandForText
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                        style: style(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        final character = SizedBox(
          key: const Key('tip-character'),
          width: characterWidth,
          height: height,
          child: ExcludeSemantics(
            child:
                a.character == TipCharacter.guide
                    ? Transform.flip(
                      flipX: a.characterOnRight,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            width: 840,
                            height: 880,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minWidth: 1024,
                                maxWidth: 1024,
                                minHeight: 1536,
                                maxHeight: 1536,
                                child: Image.asset(
                                  'assets/characters/nara_guide.png',
                                  width: 1024,
                                  height: 1536,
                                  fit: BoxFit.fill,
                                  cacheWidth: 320,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    : CustomPaint(painter: _DeerPainter()),
          ),
        );
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: SizedBox(
            key: const Key('tips-region'),
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (a.showCharacter && !a.characterOnRight) character,
                bubble,
                if (a.showCharacter && a.characterOnRight) character,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(
    this.background,
    this.border,
    this.radius,
    this.tail,
    this.right,
  );
  final Color background, border;
  final double radius;
  final bool tail, right;
  @override
  void paint(Canvas canvas, Size size) {
    var path =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    if (tail) {
      final x = right ? size.width : 0.0;
      final direction = right ? 1.0 : -1.0;
      final triangle =
          Path()
            ..moveTo(x - direction * 2, size.height * 0.58)
            ..lineTo(x + direction * 10, size.height * 0.77)
            ..lineTo(x - direction * 2, size.height * 0.78)
            ..close();
      path = Path.combine(PathOperation.union, path, triangle);
    }
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.3), 3, false);
    canvas.drawPath(path, Paint()..color = background);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      background != old.background ||
      border != old.border ||
      radius != old.radius ||
      tail != old.tail ||
      right != old.right;
}

class _DeerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, (size.height - size.width * 1.2) / 2);
    canvas.scale(size.width / 100);
    final brown =
        Paint()
          ..color = const Color(0xFF67412F)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      final x = 50 + side * 20.0;
      canvas.drawLine(Offset(x, 38), Offset(x + side * 6, 5), brown);
      canvas.drawLine(
        Offset(x + side * 4, 20),
        Offset(x + side * 16, 10),
        brown,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(50 + side * 34.0, 45),
          width: 25,
          height: 18,
        ),
        Paint()..color = const Color(0xFFDDA66C),
      );
    }
    canvas.drawOval(
      const Rect.fromLTWH(13, 30, 74, 75),
      Paint()..color = const Color(0xFFE8B67A),
    );
    canvas.drawOval(
      const Rect.fromLTWH(24, 70, 52, 32),
      Paint()..color = const Color(0xFFFFEBD0),
    );
    for (final x in [34.0, 66.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 62), width: 10, height: 14),
        brown,
      );
      canvas.drawCircle(Offset(x - 2, 59), 2, Paint()..color = Colors.white);
    }
    canvas.drawOval(const Rect.fromLTWH(44, 78, 12, 8), brown);
    canvas.drawArc(
      const Rect.fromLTWH(38, 79, 24, 14),
      0,
      3.14,
      false,
      brown
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DeerPainter old) => false;
}

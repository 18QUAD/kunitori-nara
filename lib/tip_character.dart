import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tip_appearance.dart';

class TipCharacterView extends StatefulWidget {
  const TipCharacterView({
    super.key,
    required this.appearance,
    required this.speechKey,
    this.nextSpeechAt,
    this.lipSyncDuration,
    this.expression = TipExpression.neutral,
  });
  final TipAppearance appearance;
  final Object speechKey;
  final DateTime? nextSpeechAt;
  final Duration? lipSyncDuration;
  final TipExpression expression;

  @override
  State<TipCharacterView> createState() => _TipCharacterViewState();
}

class _TipCharacterViewState extends State<TipCharacterView>
    with WidgetsBindingObserver {
  final _random = math.Random();
  Timer? _blinkTimer, _blinkEnd, _mouthTimer, _mouthEnd;
  bool _eyesClosed = false, _mouthClosed = false;
  bool _active = false, _expressionsCached = false;
  late DateTime _speechStartedAt;

  @override
  void initState() {
    super.initState();
    _speechStartedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheExpressions();
    _restart();
  }

  @override
  void didUpdateWidget(TipCharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _precacheExpressions();
    if (oldWidget.speechKey != widget.speechKey) {
      _speechStartedAt = DateTime.now();
    }
    if (oldWidget.appearance.character != widget.appearance.character ||
        oldWidget.appearance.blinkEnabled != widget.appearance.blinkEnabled ||
        oldWidget.appearance.lipSyncEnabled !=
            widget.appearance.lipSyncEnabled) {
      _restart();
    } else if (oldWidget.speechKey != widget.speechKey ||
        oldWidget.nextSpeechAt != widget.nextSpeechAt ||
        oldWidget.lipSyncDuration != widget.lipSyncDuration ||
        oldWidget.expression != widget.expression) {
      _restart(resetBlink: false);
    }
  }

  void _precacheExpressions() {
    if (_expressionsCached ||
        widget.appearance.character != TipCharacter.guide) {
      return;
    }
    _expressionsCached = true;
    for (final suffix in [
      '_joy',
      '_joy_face_parts',
      '_sad',
      '_sad_face_parts',
    ]) {
      unawaited(
        precacheImage(
          ResizeImage.resizeIfNeeded(
            320,
            null,
            AssetImage('assets/characters/nara_guide$suffix.png'),
          ),
          context,
        ),
      );
    }
  }

  void _cancel() {
    _blinkTimer?.cancel();
    _blinkEnd?.cancel();
    _mouthTimer?.cancel();
    _mouthEnd?.cancel();
  }

  void _restart({bool resetBlink = true}) {
    _mouthTimer?.cancel();
    _mouthEnd?.cancel();
    if (resetBlink) {
      _blinkTimer?.cancel();
      _blinkEnd?.cancel();
      _eyesClosed = false;
    }
    _mouthClosed = widget.appearance.character == TipCharacter.deer;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active =
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (!_active) {
      _cancel();
      return;
    }
    if (resetBlink && widget.appearance.blinkEnabled) _scheduleBlink();
    if (!widget.appearance.lipSyncEnabled) return;
    final duration = widget.lipSyncDuration;
    final changeAt = widget.nextSpeechAt;
    final untilStop =
        duration != null
            ? _speechStartedAt.add(duration).difference(DateTime.now())
            : changeAt == null
            ? null
            : changeAt.difference(DateTime.now()) - const Duration(seconds: 1);
    if (untilStop != null && untilStop <= Duration.zero) {
      _mouthClosed = true;
      return;
    }
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (mounted) setState(() => _mouthClosed = !_mouthClosed);
    });
    if (untilStop != null) {
      _mouthEnd = Timer(untilStop, () {
        _mouthTimer?.cancel();
        if (mounted) setState(() => _mouthClosed = true);
      });
    }
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(
      Duration(milliseconds: 3000 + _random.nextInt(3000)),
      () {
        if (!mounted) return;
        setState(() => _eyesClosed = true);
        _blinkEnd = Timer(const Duration(milliseconds: 130), () {
          if (!mounted) return;
          setState(() => _eyesClosed = false);
          _scheduleBlink();
        });
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(_restart);
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _guideAsset({required bool parts}) {
    final suffix = switch (widget.expression) {
      TipExpression.neutral => '',
      TipExpression.joyful => '_joy',
      TipExpression.disappointed => '_sad',
    };
    return 'assets/characters/nara_guide$suffix${parts ? '_face_parts' : ''}.png';
  }

  @override
  Widget build(BuildContext context) =>
      widget.appearance.character == TipCharacter.guide
          ? Transform.flip(
            flipX: widget.appearance.characterOnRight,
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
                      child: SizedBox(
                        width: 1024,
                        height: 1536,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              _guideAsset(parts: false),
                              cacheWidth: 320,
                              fit: BoxFit.fill,
                            ),
                            if (_eyesClosed)
                              ClipPath(
                                key: const Key('guide-closed-eyes'),
                                clipper: const _GuideFaceClipper(eyes: true),
                                child: Image.asset(
                                  _guideAsset(parts: true),
                                  cacheWidth: 320,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            if (_mouthClosed)
                              ClipPath(
                                key: const Key('guide-closed-mouth'),
                                clipper: const _GuideFaceClipper(eyes: false),
                                child: Image.asset(
                                  _guideAsset(parts: true),
                                  cacheWidth: 320,
                                  fit: BoxFit.fill,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          : CustomPaint(
            key: const Key('deer-face-parts'),
            painter: DeerCharacterPainter(
              eyesClosed: _eyesClosed,
              mouthClosed: _mouthClosed,
              expression: widget.expression,
            ),
          );
}

class _GuideFaceClipper extends CustomClipper<Path> {
  const _GuideFaceClipper({required this.eyes});
  final bool eyes;
  @override
  Path getClip(Size size) =>
      eyes
          ? (Path()
            ..addRect(const Rect.fromLTWH(375, 527, 148, 132))
            ..addRect(const Rect.fromLTWH(607, 493, 115, 130)))
          : (Path()..addRect(const Rect.fromLTWH(530, 632, 90, 80)));
  @override
  bool shouldReclip(_GuideFaceClipper old) => old.eyes != eyes;
}

class DeerCharacterPainter extends CustomPainter {
  const DeerCharacterPainter({
    this.eyesClosed = false,
    this.mouthClosed = false,
    this.expression = TipExpression.neutral,
  });
  final bool eyesClosed, mouthClosed;
  final TipExpression expression;
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
    final joyful = expression == TipExpression.joyful;
    final sad = expression == TipExpression.disappointed;
    if (joyful) {
      for (final x in [23.0, 77.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, 76), width: 12, height: 7),
          Paint()..color = const Color(0xFFF39B94),
        );
      }
    }
    for (final x in [34.0, 66.0]) {
      if (sad) {
        final left = x < 50;
        canvas.drawLine(
          Offset(x - 6, left ? 52 : 49),
          Offset(x + 6, left ? 49 : 52),
          Paint()
            ..color = const Color(0xFF67412F)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
      if (eyesClosed) {
        if (joyful || sad) {
          canvas.drawArc(
            Rect.fromLTWH(x - 6, 59, 12, 8),
            joyful ? math.pi : 0,
            math.pi,
            false,
            Paint()
              ..color = const Color(0xFF67412F)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawLine(Offset(x - 5, 62), Offset(x + 5, 62), brown);
        }
      } else {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, 62),
            width: 10,
            height:
                sad
                    ? 9
                    : joyful
                    ? 16
                    : 14,
          ),
          brown,
        );
        canvas.drawCircle(Offset(x - 2, 59), 2, Paint()..color = Colors.white);
      }
    }
    canvas.drawOval(const Rect.fromLTWH(44, 78, 12, 8), brown);
    if (mouthClosed) {
      canvas.drawArc(
        sad
            ? const Rect.fromLTWH(38, 88, 24, 14)
            : const Rect.fromLTWH(38, 79, 24, 14),
        sad ? math.pi : 0,
        math.pi,
        false,
        brown
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawOval(
        sad
            ? const Rect.fromLTWH(44, 89, 12, 7)
            : joyful
            ? const Rect.fromLTWH(39, 86, 22, 16)
            : const Rect.fromLTWH(40, 87, 20, 13),
        brown,
      );
      if (!sad) {
        canvas.drawOval(
          const Rect.fromLTWH(44, 94, 12, 4),
          Paint()..color = const Color(0xFFF39B94),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DeerCharacterPainter old) =>
      old.eyesClosed != eyesClosed ||
      old.mouthClosed != mouthClosed ||
      old.expression != expression;
}

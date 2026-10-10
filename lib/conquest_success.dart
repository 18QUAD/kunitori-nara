import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A bounded celebration: the result remains readable after the particles stop.
class ConquestSuccess extends StatelessWidget {
  const ConquestSuccess({super.key, required this.cityName});

  final String cityName;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
      duration:
          reducedMotion ? Duration.zero : const Duration(milliseconds: 2400),
      builder: (context, progress, child) {
        final entrance = Curves.easeOutBack.transform(
          (progress * 5).clamp(0.0, 1.0),
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _CelebrationPainter(progress)),
              ),
            ),
            Transform.scale(scale: 0.8 + entrance * 0.2, child: child),
          ],
        );
      },
      child: Dialog(
        backgroundColor: const Color(0xFF192A3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFEEC47C), width: 2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFEEC47C),
                  size: 80,
                ),
                const SizedBox(height: 16),
                Semantics(
                  namesRoute: true,
                  header: true,
                  child: const Text(
                    '制圧成功',
                    style: TextStyle(
                      color: Color(0xFFEEC47C),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  cityName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'すごい、5問とも正解だよ！',
                  style: TextStyle(color: Color(0xFF7AE1BB), fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text('$cityNameを制圧できたね。おめでとう！', textAlign: TextAlign.center),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('地図へ戻る'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  const _CelebrationPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;
    final random = math.Random(39);
    final paint = Paint();
    const colors = [Color(0xFFEEC47C), Color(0xFF7AE1BB), Color(0xFFFFFFFF)];
    final fade = (1 - progress * progress).clamp(0.0, 1.0);
    for (var i = 0; i < 90; i++) {
      final startX = random.nextDouble() * size.width;
      final drift = (random.nextDouble() - 0.5) * 180;
      final speed = 0.6 + random.nextDouble() * 0.7;
      final startY = -random.nextDouble() * size.height * 0.4;
      final rotation = random.nextDouble() * math.pi + progress * 8;
      paint.color = colors[i % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(
        startX + drift * progress,
        startY + progress * size.height * speed,
      );
      canvas.rotate(rotation);
      canvas.drawRect(const Rect.fromLTWH(-3, -6, 6, 12), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

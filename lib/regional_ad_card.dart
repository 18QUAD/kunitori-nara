import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'regional_ads.dart';

class RegionalAdCard extends StatefulWidget {
  const RegionalAdCard({
    super.key,
    required this.ad,
    required this.cityName,
    required this.maxHeight,
    this.onOpen,
    this.embedded = false,
    this.foreground = const Color(0xFF382D20),
  });
  final RegionalAd ad;
  final String cityName;
  final double maxHeight;
  final ValueChanged<Uri>? onOpen;
  final bool embedded;
  final Color foreground;

  @override
  State<RegionalAdCard> createState() => _RegionalAdCardState();
}

class _RegionalAdCardState extends State<RegionalAdCard> {
  RegionalAd? _pressedAd;
  RegionalAd get ad => widget.ad;
  String get cityName => widget.cityName;
  double get maxHeight => widget.maxHeight;
  bool get embedded => widget.embedded;
  Color get foreground => widget.foreground;

  Future<void> _open(BuildContext context, RegionalAd target) async {
    if (widget.onOpen != null) {
      widget.onOpen!(target.url);
      return;
    }
    try {
      if (await launchUrl(
        target.url,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        return;
      }
    } catch (_) {
      /* Keep gameplay available if the browser rejects the link. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('リンクを開けませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final height = math.min(maxHeight, box.maxHeight);
      final compact = height < 78;
      final padding = embedded ? 4.0 : 8.0;
      final width = math.max(0.0, box.maxWidth - padding * 2);
      final secondary = foreground.withValues(alpha: .8);
      Widget line(
        String text,
        double size, {
        int lines = 1,
        bool bold = false,
      }) => Text(
        text,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: bold ? foreground : secondary,
          fontSize: size,
          height: 1.1,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      );
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: SizedBox(
          key: const Key('regional-ad-card'),
          height: height,
          child: Material(
            color: embedded ? Colors.transparent : const Color(0xFFFFF2D7),
            borderRadius: BorderRadius.circular(embedded ? 8 : 16),
            clipBehavior: Clip.antiAlias,
            child: Listener(
              onPointerDown: (_) => _pressedAd = ad,
              onPointerCancel: (_) => _pressedAd = null,
              child: InkWell(
                onTap: () {
                  final target = _pressedAd ?? ad;
                  _pressedAd = null;
                  _open(context, target);
                },
                child: Semantics(
                  button: true,
                  label:
                      '広告、$cityNameの${ad.label}、${ad.advertiser}、${ad.name}、${ad.service}で詳細を見る',
                  child: Padding(
                    padding: EdgeInsets.all(padding),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: width,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (!compact && width >= 200 && ad.imageUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 42,
                                  height: 54,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Image.network(
                                          ad.imageUrl.toString(),
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (_, __, ___) => Icon(
                                                Icons.storefront,
                                                color: foreground,
                                                size: 28,
                                              ),
                                        ),
                                      ),
                                      if (ad.category == 'hotel')
                                        const Positioned(
                                          left: 0,
                                          bottom: 0,
                                          child: ColoredBox(
                                            color: Colors.white,
                                            child: Text(
                                              '楽天トラベル',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 8,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  line('PR · $cityName · ${ad.label}', 9),
                                  if (ad.advertiser != ad.name)
                                    line(ad.advertiser, 11, bold: true),
                                  line(
                                    ad.name,
                                    12,
                                    lines: compact ? 1 : 2,
                                    bold: true,
                                  ),
                                  line('${ad.service}で詳細を見る ↗', 9),
                                ],
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
          ),
        ),
      );
    },
  );
}

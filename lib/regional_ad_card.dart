import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'regional_ads.dart';
import 'ad_credit.dart';

class RegionalAdCard extends StatelessWidget {
  const RegionalAdCard({
    super.key,
    required this.ad,
    required this.cityName,
    required this.maxHeight,
    this.onOpen,
  });
  final RegionalAd ad;
  final String cityName;
  final double maxHeight;
  final VoidCallback? onOpen;

  Future<void> _open(BuildContext context) async {
    if (onOpen != null) {
      onOpen!();
      return;
    }
    try {
      if (await launchUrl(
        ad.url,
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
      final compact = height < 85;
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: SizedBox(
          key: const Key('regional-ad-card'),
          height: height,
          child: Material(
            color: const Color(0xFFFFF2D7),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              child: Semantics(
                button: true,
                label:
                    '広告、$cityNameの${ad.label}、${ad.advertiser}、${ad.name}、${ad.service}で詳細を見る',
                child: Padding(
                  padding: EdgeInsets.all(compact ? 6 : 10),
                  child: Row(
                    children: [
                      if (!compact &&
                          box.maxWidth >= 340 &&
                          ad.imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 64,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.network(
                                    ad.imageUrl.toString(),
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (_, __, ___) => const Icon(
                                          Icons.storefront,
                                          color: Color(0xFF382D20),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'PR · $cityName · ${ad.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF72582A),
                                fontSize: 10,
                              ),
                            ),
                            if (!compact)
                              Text(
                                ad.advertiser,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF382D20),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                ad.name,
                                maxLines: compact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF382D20),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '${ad.service}で詳細を見る ↗',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF72582A),
                                fontSize: 10,
                              ),
                            ),
                            if (!compact)
                              const SizedBox(height: 14, child: AdCredit()),
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
      );
    },
  );
}
